=========
Scripting
=========

A script is just a file of shell commands, one per line, run with ``run``. The
shell also has a tiny expression language: 26 integer variables, arithmetic, a
conditional, and a counted loop.

Variables and expressions
=========================

There are 26 integer (16-bit) variables, ``a`` through ``z``. Assign one with
``set``; an expression may mix literals and other variables:

.. code-block:: text

   $ set x 5
   $ set y $x + 3 * 2
   $ say $y
   16

``$x`` anywhere on a line expands to the decimal value of variable ``x`` before
the command runs. Expressions use ``+ - * /`` evaluated **left to right, with no
precedence**: ``$x + 3 * 2`` is ``(5 + 3) * 2 = 16``.

Expansion timing and the ``\$`` escape
======================================

``$x`` expands **when the line runs**. For a command redirected into a file,
that is at *write* time, so the variable's current value is baked into the file:

.. code-block:: text

   $ set n 9
   $ say got $n >> f     # writes "got 9" -- the value, not the reference
   $ cat f
   got 9

To save a **literal** ``$x`` into a file — so a script re-evaluates it each time
it runs — escape the dollar with a backslash, ``\$``:

.. code-block:: text

   $ set m 5
   $ say say got \$m >> g    # writes the literal "say got $m"
   $ run g
   got 5
   $ set m 9
   $ run g                   # re-renders: now prints "got 9"

Conditionals
============

``if <a> <op> <b> <command>`` runs ``<command>`` when the comparison holds. The
operators are two-letter mnemonics — ``eq ne lt le gt ge`` — chosen so they
never collide with the ``>`` / ``<`` redirection operators:

.. code-block:: text

   $ if 5 gt 3 say yes
   yes
   $ if 2 gt 9 say no

Loops
=====

``rep <n> <command>`` runs ``<command>`` ``n`` times:

.. code-block:: text

   $ rep 3 say hi
   hi
   hi
   hi

Building and running a script
=============================

Write the script with redirection, then ``run`` it:

.. code-block:: text

   $ say sbi 0x37 5 >> flash      # PB5 = output
   $ say sbi 0x38 5 >> flash      # PB5 high
   $ say slp 20 >> flash          # wait ~0.25 s
   $ say cbi 0x38 5 >> flash      # PB5 low
   $ run flash

A script's effects persist: a ``set`` inside the script updates the same
variables the interactive shell sees.

Limits
======

* Lines are at most 62 characters.
* Scripts run **one level deep**: a ``run`` or a nested ``rep`` inside a
  running script is not re-entered.
