# Configuration file for the Sphinx documentation builder.
#
# Full option list: https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------

project = "ikOS"
copyright = "2026, The ikOS Authors"
author = "The ikOS Authors"

language = "en"
release = "0.1.0-dev1"
version = "0.1"

# -- General configuration ---------------------------------------------------

import os
import sys

# Make the bundled ik domain extension importable (shared with the ik8b manual:
# it lets ``.. function::`` document kernel routines by their @-sigil signature).
sys.path.insert(0, os.path.abspath("_ext"))

extensions = [
    "sphinx.ext.todo",
    "sphinx.ext.ifconfig",
    "ikdomain",
]

# Let ``.. function::`` and ``:func:`` resolve to the ik domain by default.
primary_domain = "ik"

templates_path = ["_templates"]
exclude_patterns = []

html_short_title = "ikOS 0.1.0-dev1 documentation"

# Never fail the build on a missing cross-reference while the manual is written.
nitpicky = False

# There is no Pygments lexer for the ik language or the ikOS shell, so code
# blocks default to plain ``text`` highlighting rather than guessing.
highlight_language = "text"

rst_prolog = """
.. role:: ikkw(literal)
.. role:: iktype(literal)
"""

# -- Options for HTML output -------------------------------------------------

# Clean, neutral theme; fall back to the built-in Alabaster theme so the build
# never fails if Furo is not installed.
try:
    import furo  # noqa: F401

    html_theme = "furo"
except ImportError:
    html_theme = "alabaster"

html_static_path = ["_static"]
html_css_files = ["custom.css"]

# Iki, the ikOS mascot, as the sidebar logo and the browser favicon.
html_logo = "_static/iki.svg"
html_favicon = "_static/iki.svg"

html_title = "ikOS Reference Manual"

# -- Extension configuration -------------------------------------------------

todo_include_todos = False
