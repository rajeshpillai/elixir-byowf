# Ebook Builder

Generates a single PDF book from all tutorial markdown files (Steps 00–44).

## Prerequisites

**Python 3.x** with the `markdown` package:

```bash
pip install markdown
```

**wkhtmltopdf** for HTML-to-PDF conversion:

```bash
# Ubuntu/Debian
sudo apt install wkhtmltopdf

# macOS
brew install wkhtmltopdf
```

## Usage

Run from the project root:

```bash
python3 scripts/ebook/build_pdf.py
```

The PDF will be generated at:

```
tutorial/ignite-tutorial-book.pdf
```

## Output

- **Format:** A4, styled with dark code blocks, tables, and page numbers
- **Title page:** Book title, author, credits, and date
- **Table of Contents:** All 45 chapters listed
- **Content:** All tutorials rendered in order (Steps 00–44)

## Customization

Edit the metadata constants at the top of `build_pdf.py`:

```python
TITLE = "Ignite"
SUBTITLE = "Build a Phoenix-like Web Framework from Scratch"
AUTHOR = "Rajesh Pillai"
CREDITS = "Algorisys Open Source Team"
DATE = "March 2026"
```
