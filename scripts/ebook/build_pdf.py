#!/usr/bin/env python3
"""Build a single PDF book from all tutorial markdown files.

Requirements:
    - Python 3.x
    - python3-markdown (pip install markdown)
    - wkhtmltopdf (apt install wkhtmltopdf)

Usage:
    python3 scripts/ebook/build_pdf.py
"""

import glob
import markdown
import subprocess
import os
import sys

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
TUTORIAL_DIR = os.path.join(PROJECT_ROOT, "tutorial")
OUTPUT_HTML = os.path.join(TUTORIAL_DIR, "_book.html")
OUTPUT_PDF = os.path.join(TUTORIAL_DIR, "ignite-tutorial-book.pdf")

# Book metadata
TITLE = "Ignite"
SUBTITLE = "Build a Phoenix-like Web Framework from Scratch"
TAGLINE = "A Step-by-Step Tutorial for Elixir Beginners"
AUTHOR = "Rajesh Pillai"
CREDITS = "Algorisys Open Source Team"
DATE = "March 2026"


def check_dependencies():
    """Verify required tools are available."""
    try:
        import markdown  # noqa: F401
    except ImportError:
        print("Error: 'markdown' Python package is required.")
        print("Install with: pip install markdown")
        sys.exit(1)

    if not os.path.exists("/usr/bin/wkhtmltopdf") and not os.popen("which wkhtmltopdf").read().strip():
        print("Error: 'wkhtmltopdf' is required.")
        print("Install with: sudo apt install wkhtmltopdf")
        sys.exit(1)


def collect_markdown_files():
    """Collect all numbered tutorial markdown files in order."""
    files = sorted(glob.glob(os.path.join(TUTORIAL_DIR, "[0-9]*.md")))
    if not files:
        print(f"Error: No tutorial markdown files found in {TUTORIAL_DIR}")
        sys.exit(1)
    return files


def extract_title(filepath):
    """Extract the first H1 heading from a markdown file."""
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("# "):
                return line[2:]
    basename = os.path.basename(filepath)
    return basename.replace(".md", "").replace("-", " ").title()


def build_html(md_files):
    """Convert all markdown files into a single styled HTML document."""
    # Combine all markdown content
    combined_md = ""
    for f in md_files:
        with open(f, "r") as fh:
            combined_md += fh.read() + "\n\n---\n\n"

    # Convert markdown to HTML
    md_converter = markdown.Markdown(
        extensions=["fenced_code", "tables", "toc", "codehilite", "attr_list"],
        extension_configs={
            "codehilite": {"css_class": "highlight", "guess_lang": False}
        },
    )
    body_html = md_converter.convert(combined_md)

    # Build TOC entries
    toc_items = ""
    for f in md_files:
        title = extract_title(f)
        toc_items += f"        <li>{title}</li>\n"

    # Assemble full HTML
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<style>
@page {{
    size: A4;
    margin: 20mm 18mm 25mm 18mm;
    @bottom-center {{
        content: counter(page);
        font-size: 10px;
        color: #666;
    }}
}}

body {{
    font-family: "Segoe UI", "Helvetica Neue", Arial, sans-serif;
    font-size: 12px;
    line-height: 1.6;
    color: #1a1a1a;
    max-width: 100%;
}}

/* Title page */
.title-page {{
    text-align: center;
    padding-top: 180px;
    page-break-after: always;
}}
.title-page h1 {{
    font-size: 36px;
    color: #e44d26;
    margin-bottom: 10px;
    letter-spacing: 1px;
}}
.title-page .subtitle {{
    font-size: 18px;
    color: #555;
    margin-bottom: 60px;
}}
.title-page .author {{
    font-size: 16px;
    color: #333;
    margin-top: 40px;
}}
.title-page .credits {{
    font-size: 14px;
    color: #666;
    margin-top: 10px;
}}
.title-page .date {{
    font-size: 13px;
    color: #888;
    margin-top: 30px;
}}

/* TOC page */
.toc-page {{
    page-break-after: always;
}}
.toc-page h2 {{
    font-size: 24px;
    color: #e44d26;
    border-bottom: 2px solid #e44d26;
    padding-bottom: 8px;
}}
.toc-page ol {{
    list-style-type: none;
    padding-left: 0;
}}
.toc-page ol li {{
    padding: 4px 0;
    font-size: 13px;
    border-bottom: 1px dotted #ddd;
}}
.toc-page ol li a {{
    color: #333;
    text-decoration: none;
}}

h1 {{
    font-size: 24px;
    color: #e44d26;
    border-bottom: 2px solid #e44d26;
    padding-bottom: 6px;
    margin-top: 30px;
    page-break-before: always;
}}

h2 {{
    font-size: 18px;
    color: #2c3e50;
    border-bottom: 1px solid #eee;
    padding-bottom: 4px;
    margin-top: 24px;
}}

h3 {{
    font-size: 15px;
    color: #34495e;
    margin-top: 18px;
}}

h4 {{
    font-size: 13px;
    color: #555;
}}

code {{
    background: #f4f4f4;
    padding: 1px 5px;
    border-radius: 3px;
    font-family: "Fira Code", "Consolas", "Monaco", monospace;
    font-size: 11px;
}}

pre {{
    background: #1e1e2e;
    color: #cdd6f4;
    padding: 12px 16px;
    border-radius: 6px;
    overflow-x: auto;
    font-size: 10.5px;
    line-height: 1.5;
    page-break-inside: avoid;
}}

pre code {{
    background: none;
    padding: 0;
    color: inherit;
    font-size: inherit;
}}

blockquote {{
    border-left: 4px solid #e44d26;
    margin: 12px 0;
    padding: 8px 16px;
    background: #fff5f0;
    color: #555;
}}

table {{
    border-collapse: collapse;
    width: 100%;
    margin: 12px 0;
    font-size: 11px;
}}

th, td {{
    border: 1px solid #ddd;
    padding: 6px 10px;
    text-align: left;
}}

th {{
    background: #f8f8f8;
    font-weight: 600;
}}

tr:nth-child(even) {{
    background: #fafafa;
}}

hr {{
    border: none;
    border-top: 1px solid #eee;
    margin: 30px 0;
}}

a {{
    color: #e44d26;
    text-decoration: none;
}}

strong {{
    color: #2c3e50;
}}

img {{
    max-width: 100%;
}}

.highlight {{
    background: #1e1e2e;
    padding: 12px 16px;
    border-radius: 6px;
    overflow-x: auto;
}}
</style>
</head>
<body>

<!-- Title Page -->
<div class="title-page">
    <h1 style="page-break-before: avoid;">{TITLE}</h1>
    <div class="subtitle">{SUBTITLE}</div>
    <div class="subtitle" style="font-size: 14px; color: #888;">{TAGLINE}</div>
    <div class="author">Author: {AUTHOR}</div>
    <div class="credits">Credits: {CREDITS}</div>
    <div class="date">{DATE}</div>
</div>

<!-- Table of Contents -->
<div class="toc-page">
    <h2 style="page-break-before: avoid;">Table of Contents</h2>
    <ol>
{toc_items}    </ol>
</div>

<!-- Content -->
{body_html}

</body>
</html>
"""
    return html


def generate_pdf(html_content):
    """Write HTML to temp file and convert to PDF with wkhtmltopdf."""
    # Write intermediate HTML
    with open(OUTPUT_HTML, "w") as f:
        f.write(html_content)

    print(f"  Intermediate HTML: {OUTPUT_HTML}")

    # Convert to PDF
    cmd = [
        "wkhtmltopdf",
        "--quiet",
        "--enable-local-file-access",
        "--page-size", "A4",
        "--margin-top", "20mm",
        "--margin-bottom", "25mm",
        "--margin-left", "18mm",
        "--margin-right", "18mm",
        "--footer-center", "[page]",
        "--footer-font-size", "9",
        "--footer-spacing", "5",
        "--encoding", "UTF-8",
        OUTPUT_HTML,
        OUTPUT_PDF,
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  wkhtmltopdf error: {result.stderr}")
        sys.exit(1)

    # Clean up intermediate HTML
    os.remove(OUTPUT_HTML)

    # Report file size
    size_mb = os.path.getsize(OUTPUT_PDF) / (1024 * 1024)
    print(f"  Output: {OUTPUT_PDF} ({size_mb:.1f} MB)")


def main():
    print("Ignite Tutorial — PDF Book Builder")
    print("=" * 40)

    print("\n[1/4] Checking dependencies...")
    check_dependencies()

    print("[2/4] Collecting tutorial files...")
    md_files = collect_markdown_files()
    print(f"  Found {len(md_files)} chapters")

    print("[3/4] Building HTML...")
    html = build_html(md_files)

    print("[4/4] Generating PDF...")
    generate_pdf(html)

    print("\nDone!")


if __name__ == "__main__":
    main()
