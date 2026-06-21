# Interface-First Design — TypeScript

The contract construct is `interface` (or `type`). TypeScript is **structural**: anything with the right shape satisfies the contract, no `implements` required. That makes fakes trivial — a plain object literal of the right shape *is* an implementation — but it also means the contract is erased at runtime. The contract lives entirely in the types plus the tests that exercise it.

## `interface` vs `type`

- **`interface`** for object/contract shapes that something fulfills — services, repositories, ports, props. They're extendable and produce clearer error messages.
- **`type`** for unions, intersections, function types, mapped/conditional types, and aliases.
- Don't agonize over it; the rule of thumb above covers nearly everything.

## Designing the contract

- **Precise types, no `any`.** `any` deletes the contract. At untrusted boundaries (parsed JSON, external APIs) use `unknown` and narrow, so callers can't accidentally depend on a shape you never guaranteed.
- **Make illegal states unrepresentable.** Prefer discriminated unions over boolean flags and optional grab-bags:
  ```ts
  type FetchState<T> =
    | { status: "loading" }
    | { status: "error"; error: FetchError }
    | { status: "ready"; data: T };
  ```
  The caller is forced to handle every case; there's no "ready but data is undefined" hole.
- **Literal unions / enums over magic strings.** `type Channel = "email" | "sms" | "push"` beats `string` — the compiler enumerates the valid values and rejects typos.
- **`readonly` and branded types for value objects.** `readonly` on returned arrays/objects signals the caller mustn't mutate. Branded types (`type UserId = string & { readonly __brand: "UserId" }`) stop a raw string being passed where an ID is required.
- **Errors are part of the contract.** Decide per interface: throw (document with `@throws` in the doc comment, since TS can't type it), or return a `Result<T, E>` / discriminated union. Returning errors makes them visible in the type; throwing keeps call sites clean. Pick one per boundary and be consistent.

## Dependency injection

No framework needed — dependencies are constructor or function parameters typed to the interface:

```ts
class Checkout {
  constructor(
    private readonly payments: PaymentGateway,   // interface
    private readonly orders: OrderStore,          // interface
  ) {}
}
```

A test passes a fake object literal — structural typing means no class or `implements` is required:

```ts
const fakePayments: PaymentGateway = {
  charge: async (amount, token) => ({ id: "fake_1", amount }),
};
```

If faking the dependency requires stubbing a sprawl of methods, the interface is too fat — segregate it.

## Example: a port

```ts
/**
 * Delivers a notification to one recipient.
 * Implementations are channel-specific and must be idempotent per
 * (recipient, idempotencyKey): re-sending with the same key must not
 * deliver twice.
 *
 * @throws DeliveryError when the channel rejects the message.
 * @example
 *   await notifier.send({ recipient: userId, subject, body, idempotencyKey: orderId });
 */
export interface Notifier {
  send(message: OutboundMessage): Promise<DeliveryReceipt>;
}

export interface OutboundMessage {
  readonly recipient: UserId;
  readonly subject: string;
  readonly body: string;
  readonly idempotencyKey: string;
}
```

One method, intent-named, immutable input shape, idempotency invariant and failure mode documented, usage example included. Email/SMS/push concretes follow after sign-off.
