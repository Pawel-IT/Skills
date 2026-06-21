---
name: interface-first-design
description: Design the contract/abstraction boundary BEFORE writing implementation whenever a new feature, component, or refactor needs a clean seam between parts of the system. Use this whenever you introduce or restructure a service, repository, handler, gateway, adapter, client, provider, factory, store, controller, or value object; whenever two parts of the system need to communicate through a defined boundary; whenever a class/module has grown too many responsibilities and is being split; or whenever the user says "design an API/interface/contract/protocol/trait" or "I need a clean interface for X." Applies across languages — TypeScript/JavaScript interfaces and types, PHP/Java/C# interfaces, Python Protocols/ABCs, Go interfaces, Rust traits, Swift protocols. Fire even when the user doesn't say the word "interface," as long as a real abstraction boundary is being created. ALWAYS invoke this skill when performing any code-review function or skill (e.g. /code-review, /review, /security-review, /simplify, or any diff/PR review): grade every interface or contract in the changeset against the design rubric below. Do NOT fire for bug fixes, formatting, renames, or trivial edits that don't introduce a new seam.
---

# Interface-First Design

When a new feature or refactor needs a boundary between two parts of a system, design the **contract** for that boundary before writing any implementation behind it. The contract is the method/function signatures, names, and types callers depend on — not the concrete class, struct, or module that fulfills it.

The contract is the expensive thing to get wrong. Implementations are swappable; a leaky or bloated contract propagates into every caller and test, and changing it later is a breaking change. Designing it first forces the right questions: who calls this, what do they actually need, what stays hidden.

## Workflow

1. **Identify the boundary.** Name the seam and who sits on each side — callers (consumers) and eventual implementation(s) (providers). No real boundary (one-off helper, bug fix, rename) → skill doesn't apply.
2. **Design the contract first.** Write the interface — signatures, names, types, doc comments — with no implementation behind it. Apply the principles below.
3. **Get sign-off before implementing.** Show the contract and pause; surface the tradeoffs (what you split, left out, deferred). This gate is the point — without it the "design first" discipline is lost. (If told to just proceed, propose-and-continue, but still lead with the contract.)
4. **Implement against the agreed contract,** then verify it held up. An awkward forced signature change is a signal to revisit the design, not to quietly mutate it.

## Design principles (the rubric — grade every contract)

- **Single responsibility / interface segregation.** Keep each interface small and focused. If callers use only half its methods, split it. Many narrow interfaces beat one fat one.
- **Intention-revealing names.** Name what the caller *wants*, not how it's done. `findActiveByEmail` over `query`; `Clock.now()` over `getSystemTimeMillis`.
- **Depend on abstractions, not concretions.** The interface is the dependency; implementations plug in. This makes the seam testable and swappable.
- **Designed for testing.** Dependencies passed in (constructor/parameter injection), never via globals, singletons, or ambient I/O. Test: can a caller be unit-tested with a trivial hand-written fake, no mocking-framework gymnastics?
- **General enough, not speculative.** Design for the real present callers, generalized just enough. No methods/params/hooks for hypothetical futures — extend later when the need is concrete.
- **Honest types and errors.** Make the type system carry the contract — precise types, no `any`/`mixed`/`interface{}`, enums/sum types over magic strings. Make failure modes part of the contract: declared exceptions, `Result`/`Either`, or documented in the doc comment.
- **Minimal surface, maximal hiding.** Expose the smallest set of operations callers need. Every public method is a promise. Hide construction, ordering, internal collaborators.

## Apply the language/framework idiom

Discipline is identical across stacks; the construct differs. After designing the contract, read the matching reference:

- **PHP** → `references/php.md` — `interface`+`implements`, full type declarations, PHPDoc generics/`@throws`, `readonly` value objects, constructor injection, container binding.
- **TypeScript / JavaScript** → `references/typescript.md` — `interface` vs `type`, structural typing, discriminated unions, branded value objects, `Result` vs `throw`, fakes as object literals.
- **Livewire (Laravel)** → `references/livewire.md` — the three boundaries (service contracts, component public surface, Form Objects), DI via `boot()`/method injection, events as contracts, `Livewire::test()`. Read **in addition to** `php.md`.

Any other stack: same discipline — a documented, type-annotated shape (interface, protocol, trait, duck-typed object) plus a test any implementation must pass.

## Document for humans *and* AI agents

Both read the contract without reading the implementation, so it must be self-explanatory:

- A doc comment on the interface stating purpose and invariants (ordering, idempotency, thread-safety, "call before X").
- Per-method docs: what it does, params, returns, what it throws/fails with.
- A short usage example showing a correct call — lets a future reader or AI agent call it from the signature alone.

## Review checklist (run before writing any implementation)

- [ ] Single, nameable responsibility per interface? Any caller use only part? (yes → split)
- [ ] Names describe caller intent and domain, not mechanics?
- [ ] Caller unit-testable with a trivial hand-written fake?
- [ ] All dependencies injected, not reached for globally?
- [ ] Types precise, failure modes part of the contract?
- [ ] Every method justified by a *current* caller — nothing speculative?
- [ ] Public surface the smallest that satisfies callers?
- [ ] Callable correctly from signature + doc comment alone?

Only once these pass: present for sign-off, then implement.

## Example (PHP)

A feature needs to capture inbound leads. Don't reach for a `ContactManager` class wired to Eloquent and a HubSpot client. Start with the seam:

```php
/**
 * Reads and persists CRM contacts.
 * Returns null when no contact matches — never throws for "not found."
 *
 * @throws ContactRepositoryException if the data source is unavailable.
 */
interface ContactRepository
{
    public function findByEmail(Email $email): ?Contact;

    /** @throws DuplicateContact if the email is already registered. */
    public function save(NewContact $contact): ContactId;
}
```

A `LeadCaptureHandler` injects this interface and calls it without knowing whether the store is Eloquent, HubSpot, or an in-memory fake:

```php
$contact = $this->contacts->findByEmail(new Email($input->email));

if ($contact === null) {
    $contactId = $this->contacts->save(new NewContact(
        email: new Email($input->email),
        name: new FullName($input->firstName, $input->lastName),
    ));
    $this->pipeline->openDeal($contactId, DealSource::WebForm);
}
```

Two methods, value objects at the boundary (`Email`, `NewContact`, `ContactId`), two distinct failure modes — and a trivial in-memory fake covers both. The Eloquent and HubSpot implementations come *after* sign-off.
