# Interface-First Design — Livewire (v3)

A Livewire component is **not itself an interface** — it's a view-model that bridges a Blade view and your backend. So "design the interface first" lands in three distinct places here, and all three deserve the up-front design + sign-off treatment:

1. The **service contracts** the component depends on.
2. The component's own **public surface** (its contract to the view and to other components).
3. The **Form Object** that defines the shape of user input.

Keep business logic *out* of the component. The component orchestrates; the real work lives behind injected service interfaces. That's what keeps it testable and keeps the component thin.

## 1. Inject service *interfaces* — but not via the constructor

Livewire owns the constructor (it needs the component `$id`), so **you cannot use `__construct` for dependency injection**. Two supported paths, both resolving interface → implementation from the container:

**`boot()` into a non-persisted `protected` property** — runs on every request, so the dependency is always available without being serialized into component state:

```php
final class Checkout extends Component
{
    protected PaymentGateway $payments;   // interface; protected = not persisted

    public function boot(PaymentGateway $payments): void
    {
        $this->payments = $payments;
    }
}
```

**Method injection on the action** — cleanest when only one action needs it:

```php
public function place(OrderRepository $orders): void
{
    $orders->add(/* ... */);
}
```

Never type a service as a `public` property — public properties are hydrated/dehydrated as state and a service isn't serializable. Bind the interface in a service provider as usual (`$this->app->bind(PaymentGateway::class, StripeGateway::class)`). See `php.md` for designing those service interfaces themselves.

## 2. The component's public surface IS a contract

Everything `public` on the component is the API the Blade view (and other components) bind to. Design it as deliberately as any interface — small, intention-named, minimal:

- **Public properties** = the state the template reads/writes (`wire:model`). Expose only what the view binds to. Don't dump an Eloquent model in as a fat public property; expose the specific fields.
- **Public methods** = the actions the template can invoke (`wire:click`). Every public method is callable from the front end — treat that as your action API and keep it tight. Anything internal should be `protected`/`private`.
- **`#[Locked]`** on properties the client must not mutate (IDs, prices). This is part of the contract: it says "read-only to the view."
- **`#[Computed]`** for derived state instead of stuffing computed values into public properties — keeps the persisted surface small and the derivation honest.
- **Events** are the contract *between* components. Name them and pin their payload shape deliberately:
  ```php
  $this->dispatch('order-placed', orderId: $order->id);   // emitter
  #[On('order-placed')] public function refresh(string $orderId): void { /* ... */ }
  ```
  Treat the event name + payload like a function signature: changing it breaks every listener.

## 3. Form Objects are the input boundary

Put user input behind a Form Object (`extends Livewire\Form`) rather than scattering loose public properties + validation across the component. The form is the clean, validated shape of "what the user is submitting":

```php
class OrderForm extends Form
{
    #[Validate('required|email')]
    public string $email = '';

    #[Validate('required|array|min:1')]
    public array $lineItems = [];
}
```

```php
final class Checkout extends Component
{
    public OrderForm $form;

    public function place(OrderRepository $orders): void
    {
        $this->form->validate();
        // hand the validated data to a service interface — not business logic here
    }
}
```

Form Objects can't take constructor DI either; if `store()`-style logic needs a service, inject it into the component's action and pass it in, or resolve it in `boot()`.

## Testing

`Livewire::test()` drives the component; swap the bound interface for a fake so no real I/O happens:

```php
$this->app->bind(PaymentGateway::class, FakePaymentGateway::class);

Livewire::test(Checkout::class)
    ->set('form.email', 'a@b.com')
    ->call('place')
    ->assertDispatched('order-placed')
    ->assertHasNoErrors();
```

If you can't test an action without hitting the database or a real API, the component is doing work that belongs behind an injected interface — pull it out.

## The sign-off gate for a Livewire feature

Before writing the component, present and get agreement on:

- The **service interface(s)** the component will depend on (designed per `php.md`).
- The component's **public surface**: which properties are bound, which are `#[Locked]`, which are `#[Computed]`; the public action methods; the events dispatched and listened for, with their payload shapes.
- The **Form Object** shape and validation rules.

Only then wire up the component and its Blade view.
