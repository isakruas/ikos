=======================
Processes and jobs
=======================

ikOS runs up to **three** processes (``NPROC = 3``): the shell plus two more.
Scheduling is cooperative — see :doc:`/internals/scheduler` for the mechanism;
this page covers what you see from the shell.

Inspecting processes
====================

.. code-block:: text

   $ ps          # one line per live process: pid and state (R/X/S)
   0 X
   $ mem         # how many process slots are in use
   P: 1/3
   $ uptime      # the timer tick count since boot
   T: 1234

In ``ps`` the state letter is ``R`` ready, ``X`` running, ``S`` sleeping.

Background jobs
===============

``run`` blocks until the script finishes. Appending ``&`` runs the script as its
own process, which yields between commands so the shell stays responsive:

.. code-block:: text

   $ run flash &    # the script runs in the background
   $ ps             # the job now shows up as a second process
   0 X
   1 R
   $ uptime         # the shell is still usable while it runs

A background job occupies one of the three process slots for its lifetime. Stop
a process with ``kill <pid>``; ``kill`` refuses out-of-range pids.

Cooperative scheduling, briefly
===============================

A process keeps the CPU until it yields — by waiting for input, sleeping, or
exiting. The Timer0 interrupt only advances the tick counter (``uptime``) and
wakes sleeping processes; it does **not** preempt a running process. There are
no priorities. Long, tight loops in one process therefore starve the others
until they yield, so background scripts yield between each command.
