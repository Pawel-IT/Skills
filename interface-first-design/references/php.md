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

## Example: a repository contract

```php
/**
 * Reads and persists User aggregates.
 * Implementations must treat email as a unique key.
 *
 * @example
 *   $user = $users->findByEmail(new Email('a@b.com'))
 *       ?? throw new UserNotFound();
 */
interface UserRepository
{
    public function findByEmail(Email $email): ?User;

    /** @return list<User> */
    public function activeSince(DateTimeImmutable $since): array;

    /** @throws DuplicateEmail */
    public function add(User $user): void;
}
```

Small, role-named (`UserRepository`, not `UserManager`), value objects at the boundary (`Email`, not `string`), failure modes declared, array shape pinned in PHPDoc, usage example for the next reader. The Eloquent/Doctrine implementation comes only after this is signed off.
