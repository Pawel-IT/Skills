# Interface-First Design — PHP

The contract construct is `interface`, fulfilled with `implements`. PHP interfaces are **nominal** (a class satisfies an interface only by explicitly implementing it), so the binding from abstraction to implementation is wired in the container, not inferred.

## Designing the contract

- **Full type declarations, always.** Every parameter and return value gets a type. Use union types (`int|string`), nullable (`?User`), and `void`/`never`/`static` where they sharpen the contract. The signature is the first line of documentation.
- **Push what the type system can't say into PHPDoc.** PHP types are coarse, so annotate:
  - Array shapes: `@return list<User>`, `@param array{id: int, email: string} $row`
  - Generics: `@template T` on the interface, `@return T` on methods (for collections, repositories, result wrappers)
  - Failure modes: `@throws NotFoundException` — make every exception a caller can expect part of the contract.
- **Enums over magic strings/constants.** A backed enum (`enum Status: string`) in a signature is self-documenting and exhaustively checkable; `string $status` is not.
- **`readonly` for value objects.** Inputs and outputs that should be immutable (IDs, money, DTOs) use `readonly` promoted constructor properties. An immutable value object passed across the boundary can't be mutated by either side behind the other's back.
- **Named constructors behind factories.** If construction is non-trivial, put it behind a factory interface (`UserFactory::fromRegistration(...)`) rather than a fat public constructor, so callers depend on intent, not assembly.
- **PSR-12** formatting throughout.

## Dependency injection & wiring

PHP classes (services, not framework-managed view-models) take their collaborators through **constructor injection**, typed to interfaces:

```php
final class CheckoutService
{
    public function __construct(
        private readonly PaymentGateway $payments,   // interface
        private readonly OrderRepository $orders,     // interface
    ) {}
}
```

Bind interface → implementation once, in a service provider (Laravel) or container config:

```php
$this->app->bind(PaymentGateway::class, StripeGateway::class);
```

Callers and tests depend on `PaymentGateway`, never on `StripeGateway`.

## Testability check

Because dependencies are injected interfaces, a unit test hands the service a hand-written fake — no mocking framework needed:

```php
final class FakePaymentGateway implements PaymentGateway
{
    public array $charged = [];
    public function charge(Money $amount, CardToken $token): ChargeReceipt
    {
        $this->charged[] = $amount;
        return new ChargeReceipt(id: 'fake_1', amount: $amount);
    }
}
```

If you *can't* write a trivial fake — because the contract is fat, or the real work is reachable only through a static facade/global — that's the signal to fix the contract, not the test.

## Example: a CRM pipeline repository

```php
/**
 * Persists and retrieves leads within the CRM pipeline.
 * "Not found" → null return. Exceptions mean the source is unavailable.
 * findByStage() returns leads newest-first by created_at.
 *
 * @throws LeadRepositoryException if the data source is unreachable.
 */
interface LeadRepository
{
    public function findById(LeadId $id): ?Lead;

    /** @return list<Lead> Ordered newest-first by created_at. */
    public function findByStage(LeadStage $stage): array;

    /** $lead has no id yet; assigns and returns one. @throws DuplicateLead if the email already exists. */
    public function save(NewLead $lead): LeadId;

    /** Records the transition timestamp alongside the stage change. */
    public function advanceStage(LeadId $id, LeadStage $to): void;
}
```

**Deliberately omitted:**
- `deleteById()` — no caller needs it yet; add when one does
- `findByAssignedUser()` — belongs in a separate read-side query contract, not here. findByStage is part of the lead's own lifecycle. findByAssignedUser is a cross-cutting query about a collection. Same DB table, different seam

Value objects (`LeadId`, `NewLead`) and a backed enum (`LeadStage`) carry the contract instead of primitives. The ordering invariant and failure modes are in the doc comment, not hidden in an implementation. The fake is four in-memory methods — no mocking framework needed. Eloquent and HubSpot implementations come after sign-off.
