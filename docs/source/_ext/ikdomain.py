"""A minimal Sphinx domain for the ik language.

It provides a single directive, ``.. function::``, for documenting ik
functions and intrinsics using their real ``@``-sigil signatures, and a matching
``:func:`` cross-reference role plus a general index entry for each. A dedicated
domain is needed because ik signatures use ``@`` and ``$`` sigils that the
built-in language domains cannot parse.

Usage in reStructuredText::

    .. function:: @delay_ms($ms: u16)

       Delay for approximately ``$ms`` milliseconds.

    See :func:`@delay_ms <delay_ms>` for the blocking wait.

The cross-reference target is the bare function name (the identifier after the
optional ``@``), so ``:func:`@delay_ms <delay_ms>``` and ``:func:`delay_ms```
both resolve.
"""

import re

from docutils import nodes
from sphinx import addnodes
from sphinx.directives import ObjectDescription
from sphinx.domains import Domain, ObjType
from sphinx.roles import XRefRole
from sphinx.util.nodes import make_refnode

_NAME_RE = re.compile(r"@?([A-Za-z_][A-Za-z0-9_]*)")


def _func_name(sig):
    match = _NAME_RE.match(sig.strip())
    return match.group(1) if match else sig.strip()


class IkFunction(ObjectDescription):
    """Describe an ik function or intrinsic from its full signature."""

    def handle_signature(self, sig, signode):
        signode += addnodes.desc_name(sig, sig)
        return _func_name(sig)

    def add_target_and_index(self, name, sig, signode):
        anchor = name
        if anchor not in self.state.document.ids:
            signode["names"].append(anchor)
            signode["ids"].append(anchor)
            self.state.document.note_explicit_target(signode)

            domain = self.env.get_domain("ik")
            domain.add_function(name, anchor)

        self.indexnode["entries"].append(
            ("single", "%s (ik function)" % name, anchor, "", None)
        )


class IkDomain(Domain):
    name = "ik"
    label = "ik"

    object_types = {
        "function": ObjType("function", "func"),
    }
    directives = {
        "function": IkFunction,
    }
    roles = {
        "func": XRefRole(),
    }
    initial_data = {
        "functions": {},  # name -> (docname, anchor)
    }

    def clear_doc(self, docname):
        for name, (doc, _anchor) in list(self.data["functions"].items()):
            if doc == docname:
                del self.data["functions"][name]

    def merge_domaindata(self, docnames, otherdata):
        for name, (doc, anchor) in otherdata["functions"].items():
            if doc in docnames:
                self.data["functions"][name] = (doc, anchor)

    def add_function(self, name, anchor):
        self.data["functions"][name] = (self.env.docname, anchor)

    def resolve_xref(self, env, fromdocname, builder, typ, target, node, contnode):
        target = _func_name(target)
        entry = self.data["functions"].get(target)
        if entry is None:
            return None
        doc, anchor = entry
        return make_refnode(builder, fromdocname, doc, anchor, contnode, target)

    def get_objects(self):
        for name, (doc, anchor) in self.data["functions"].items():
            yield (name, name, "function", doc, anchor, 1)


def setup(app):
    app.add_domain(IkDomain)
    return {
        "version": "1.0",
        "parallel_read_safe": True,
        "parallel_write_safe": True,
    }
