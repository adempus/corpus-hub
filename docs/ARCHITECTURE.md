# Corpus Hub — Architecture Concepts (Plain-English Glossary)

A companion to the [PRD](PRD.md) and the [C4 diagrams](.). This file names the
formal software-architecture concepts that make up Corpus Hub — and then explains
each one like you're talking to a curious 12-year-old. If you can say the
[one-sentence summary](#the-one-sentence-tie-together) out loud and explain every
bolded word, you understand this system at a senior level.

---

## 1. Distributed System
**Formal:** software that runs across multiple computers that talk over a network.

**Plain:** This project isn't one program on one machine. It's two computers (the Pi and big boi) passing notes over the network. More than one computer working together = "distributed."

## 2. Client–Server Model
**Formal:** one machine offers a service; others request it.

**Plain:** A restaurant. The kitchen (server) makes food; customers (clients) order it. The Pi is the kitchen — it holds all the food (documents) and takes orders (searches). Agents and the worker are the customers ordering.

## 3. Separation of Concerns
**Formal:** each part has one job and doesn't meddle in others'.

**Plain:** In a kitchen, one person chops, one cooks, one washes dishes. Nobody does everything. The Pi *serves* searches; big boi *processes* documents. When one breaks, you know exactly who to blame.

## 4. Stateful vs. Stateless
**Formal:** "stateful" remembers things between requests; "stateless" forgets after each task.

**Plain:** The Pi is the kid who keeps the diary — remembers all your books and notes. big boi is the kid who does your math homework then forgets it the instant he hands it back. Because big boi remembers nothing, you can unplug him anytime and lose nothing. That's a *feature*.

## 5. Single Source of Truth
**Formal:** one place is the official record; everyone else copies from it.

**Plain:** There's only ONE real scoreboard. If two people kept their own scores, they'd argue. The Pi is the only scoreboard — so there's never confusion about what's true.

## 6. Producer–Consumer / Message Queue
**Formal:** work is dropped into a "to-do list," and workers pick it up when free.

**Plain:** A ticket spike at a diner. Orders get clipped up (the queue); the cook grabs the next ticket when ready. Upload a book → a "ticket" goes on the spike. big boi grabs it when he wakes up. If he's asleep, tickets just wait. Nothing gets lost.

## 7. Pull-Based (vs. Push-Based)
**Formal:** does the worker *ask* for work (pull), or does the boss *shove* work at him (push)?

**Plain:** Instead of the Pi chasing big boi — "you awake?? here's work!!" — big boi walks up and asks "got anything for me?" whenever *he's* ready. The always-awake kid never wastes time knocking on a sleeping kid's door.

## 8. Asynchronous Processing
**Formal:** you don't wait for a slow task to finish; you get told later.

**Plain:** Dropping film off to be developed. You don't stand at the counter for an hour — you leave, and they call you when it's ready. Upload a book → you instantly get a "got it, working on it!" ticket instead of freezing until it's done.

## 9. Idempotency
**Formal:** doing an operation twice has the same result as doing it once.

**Plain:** A light switch labeled "ON." Flip it when it's already on? Still just on. Upload the same book twice and the system goes "already have this" instead of making a messy duplicate.

## 10. Lease (with expiry)
**Formal:** a worker "checks out" a task for a limited time; if unfinished, it frees up again.

**Plain:** A library book due in 2 weeks. big boi "borrows" a job. Finishes it? Great. Crashes and never returns it? The due date passes and the job goes back on the shelf for next time. No job gets stuck forever because someone dropped it.

## 11. Layered (Tiered) Architecture
**Formal:** the system is organized in stacked layers, each building on the one below.

**Plain:** A sandwich. Bread (raw files) → cheese (clean text) → meat (searchable index) → the plate you hand over (the search tool). Our L1→L2→L3→L4 is exactly this. Each layer only cares about the one under it.

## 12. Data Pipeline
**Formal:** data flows through processing stages, transformed at each step.

**Plain:** A car wash. The car rolls through rinse → soap → scrub → dry. A book rolls through extract → classify → chunk → embed. Enters messy, comes out finished, one station at a time.

## 13. API (Application Programming Interface)
**Formal:** a defined set of "buttons" one program presses to talk to another.

**Plain:** A vending machine. You don't reach inside — you press labeled buttons (A1, B4). Programs talk to the Pi by pressing labeled buttons like `corpus_search` and `corpus_get`. Nobody needs to know the messy insides.

## 14. Contract (Schema)
**Formal:** an agreed-upon shape for data that both sides promise to honor.

**Plain:** A pizza order form the customer and kitchen both use. Everyone fills the same boxes (size, toppings), so nobody's confused. The Pi and big boi share one form (the "bundle" shape) so they never misunderstand each other.

## 15. Caching
**Formal:** save the answer to slow work so you can reuse it instantly next time.

**Plain:** Memorizing that 7×8 = 56 instead of counting fingers every time. Ask the same search again and the Pi hands back the saved answer instead of redoing the work.

## 16. Graceful Degradation
**Formal:** when part of the system fails, the rest keeps working instead of everything crashing.

**Plain:** A car with a flat tire still drives — you don't abandon it on the highway. When big boi sleeps, you can't process *new* books, but searching existing ones works totally fine. Half-broken beats all-broken.

## 17. Fault Tolerance
**Formal:** the system expects things to break and recovers on its own.

**Plain:** A video game with autosave. If it crashes, you don't lose progress — it picks up where you were. big boi crashing mid-job? The lease expires, the job comes back, someone finishes it later. The system heals itself.

## 18. Fallback
**Formal:** a backup plan that kicks in automatically when Plan A fails.

**Plain:** Elevator's broken → you take the stairs without thinking about it. If starting big boi's fancy container fails, the system automatically runs the plain version instead. You still get where you're going.

## 19. Secrets Management
**Formal:** keep passwords/keys in a secure vault, never scattered in the code.

**Plain:** You don't tape your house key to the front door. You keep it somewhere safe and grab it when needed. Passwords live in Doppler (the safe), not written into the project where anyone could see them.

## 20. Infrastructure as Code / Declarative Config
**Formal:** you *describe* what the setup should look like, and tooling builds it for you.

**Plain:** LEGO instructions. You don't hand-glue every brick — you follow the picture and it comes out right every time, on any table. Our Docker + Makefile files are the instructions; anyone can run them and get the same system.

---

## The one-sentence tie-together

> Corpus Hub is a **distributed, layered, client–server system** where a
> **stateful, always-on Pi** (the **single source of truth**) hands documents to a
> **stateless, intermittent GPU worker** through a **pull-based message queue**,
> processes them in an **asynchronous data pipeline**, and serves cited results
> over an **API** — staying alive through **graceful degradation**,
> **fault tolerance**, and automatic **fallback**.

That sentence is the architecture's résumé.
