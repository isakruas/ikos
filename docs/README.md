<!-- Copyright (C) 2026 The ikOS Authors. SPDX-License-Identifier: GPL-3.0-or-later -->

# ikOS manual

The ikOS reference manual, built with [Sphinx](https://www.sphinx-doc.org/).

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
make html          # output in build/html/index.html
```

`make linkcheck` verifies external links; `make clean` removes the build
directory. Sources live under `source/`.
