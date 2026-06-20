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
   $ echo $y
   16

``$x`` anywhere on a line expands to the decimal value of variable ``x`` before
the command runs. Expressions use ``+ - * /`` evaluated **left to right, with no
precedence**: ``$x + 3 * 2`` is ``(5 + 3) * 2 = 16``.

Conditionals
============

``if <a> <op> <b> <command>`` runs ``<command>`` when the comparison holds. The
operators are two-letter mnemonics — ``eq ne lt le gt ge`` — chosen so they
never collide with the ``>`` / ``<`` redirection operators:

.. code-block:: text

   $ if 5 gt 3 echo yes
   yes
   $ if 2 gt 9 echo no

Loops
=====

``repeat <n> <command>`` runs ``<command>`` ``n`` times:

.. code-block:: text

   $ repeat 3 echo hi
   hi
   hi
   hi

Building and running a script
=============================

Write the script with redirection, then ``run`` it:

.. code-block:: text

   $ echo set i 0 >> flash
   $ echo repeat 8 pin b5 1 >> flash
   $ echo repeat 8 pin b5 0 >> flash
   $ run flash

A script's effects persist: a ``set`` inside the script updates the same
variables the interactive shell sees.

Limits
======

* Lines are at most 62 characters.
* Scripts run **one level deep**: a ``run`` or a nested ``repeat`` inside a
  running script is not re-entered.
