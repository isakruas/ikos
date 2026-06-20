==========================
Scheduler and processes
==========================

ikOS schedules cooperatively. Each process owns a stack and runs until it
yields; the scheduler then saves its full register + stack-pointer context and
switches to the next ready process, so a process keeps its stack and live state
across yields. There is no preemption and there are no priorities.

The process table
=================

The table is indexed by pid and lives in the kernel data region (see
:doc:`memory`). It holds, per process, a **state**, a **saved stack pointer**,
and a **wake tick** used while sleeping. The states are:

================ ====================================================
State            Meaning
================ ====================================================
``ST_UNUSED``    free slot
``ST_READY``     runnable, waiting for the CPU
``ST_RUNNING``   currently executing
``ST_SLEEPING``  waiting until its wake tick is reached
``ST_ZOMBIE``    exited, not yet reaped
================ ====================================================

``NPROC`` is 3: the shell (pid 0) plus two. Each process has a fixed stack
region; pid 0 gets the largest.

.. function:: @proc_start($pid: u8, $entry: u16)

   Admit process ``$pid``: set up its stack so the first context switch enters
   ``$entry``, and mark it ``ST_READY``.

.. function:: @scheduler()

   The kernel's main loop. Repeatedly pick the next runnable process, wake any
   sleeper whose wake tick has arrived, switch into the chosen process, and —
   when it yields — resume here. Sleeps the CPU when nothing is runnable.

Yielding: the syscalls
======================

A process returns to the scheduler through ``kernel/syscall.ik``. Each syscall
saves the caller's context, updates its state, and jumps back into the
scheduler, which later resumes the caller right after the call.

.. function:: @sys_yield()

   Voluntarily give up the CPU: mark the caller ``ST_READY`` and switch to the
   scheduler. The shell calls this while waiting for UART input, and background
   jobs call it between commands.

.. function:: @sys_sleep($ticks: u16)

   Mark the caller ``ST_SLEEPING`` with a wake tick ``$ticks`` in the future,
   then yield. The scheduler returns it to ``ST_READY`` once ``uptime`` reaches
   that tick.

.. function:: @sys_exit()

   Free the caller's slot and switch away for good.

The Timer0 tick
===============

The ``TIMER0_COMPA`` interrupt only increments the global tick counter (read by
``uptime``) and, indirectly, lets the scheduler wake sleepers. It does not force
a context switch — cooperative scheduling means a process is never interrupted
mid-computation against its will.
