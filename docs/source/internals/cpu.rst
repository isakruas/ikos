===================================
Context switching and the CPU layer
===================================

``arch/cpu.ik`` is the thin architecture layer the scheduler stands on: it
switches between process contexts and brackets critical sections. Everything
above it (the scheduler, the syscalls) is portable; the AVR-specific register
and stack handling is concentrated here.

Switching contexts
==================

A context switch saves the running process's stack pointer, then loads the next
one. Because the AVR keeps the call/return state and saved registers on the
stack, restoring a stack pointer restores a whole suspended process — it resumes
exactly where it last switched out.

.. function:: @ctx_switch($old_sp_ptr: u16, $new_sp: u16)

   Switch contexts with interrupts masked: save the current stack pointer to
   ``*$old_sp_ptr`` and load ``$new_sp``. The register save/restore around the
   stack-pointer swap is done by the ``@swtch`` primitive; ``@ctx_switch`` wraps
   it in ``@cli`` / ``@sei`` so the swap is atomic.

The scheduler calls this to enter a process and, when that process yields,
control returns here and then back to the scheduler — each side resumes after
its own ``@ctx_switch``.

Bootstrapping a new process
===========================

A process that has never run has no saved context yet. ``@proc_start`` calls
``@ctx_bootstrap`` to fake one, so the very first switch into the process
"returns" into its entry function.

.. function:: @ctx_bootstrap($stack_top: u16, $sp_slot: u16, $entry: u16)

   Lay out a fresh stack at ``$stack_top`` so the first ``@ctx_switch`` into it
   begins executing ``$entry``: push ``$entry`` as a return address (a word
   address, hence ``$entry * 2`` bytes, stored high byte first), and record the
   resulting stack pointer (``$stack_top - 2``) in the process's saved-SP slot
   at ``$sp_slot``.

Critical sections
=================

Some sequences must not be interrupted — notably a context switch, or a
read-modify-write of shared kernel state. The pair below brackets such a
section and, crucially, **restores the previous interrupt state** rather than
unconditionally re-enabling interrupts, so critical sections nest correctly.

.. function:: @irq_disable() -> u8

   Disable interrupts and return whether they were enabled (1) or already
   disabled (0), read from the ``I`` flag (bit 7) of ``SREG``.

.. function:: @irq_restore($were_on: u8)

   Re-enable interrupts only if ``$were_on`` is 1, i.e. only if the matching
   :func:`@irq_disable` found them enabled.

Use them in a save/restore pair::

   ram imut $were: u8 = @irq_disable()
   # ... critical section ...
   @irq_restore($were)
