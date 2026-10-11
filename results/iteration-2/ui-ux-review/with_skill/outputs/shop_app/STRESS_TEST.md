# shop_app — Stress Test Report (Cart + Login)

**Harness:** `test/stress_test.dart`, 97 widget tests, run with Flutter 3.44.4 on a scratch copy of the project.
**Result:** 61 passed, **36 failed**. Each failure is a real break, because every test asserts what a user would expect.

Run it: `flutter test test/stress_test.dart`

How the data gets in (the widgets were not modified):
- **Cart:** fixtures go in through `CartCubit.add()`, the app's own entry point.
- **Login:** values go in through `tester.enterText`.
- **Network:** `flutter_test` blocks real network access, so every `http` call gets an HTTP 400 with an empty body. That makes it a natural "API error" case for login and for the recommendations list.

**Matrix:**
- Sizes: 320×640, 375×812, 430×932 and 1024×768.
- Text scale: ×1.0, ×1.3 and ×2.0.
- Cart: the Demo, Worst, Empty, One and Huge (1,000) fixtures.
- Login: with and without a 336 px keyboard open.

## Phase 1 — Rendered values

| Field | Source | Type | Limit | Optional? |
|---|---|---|---|---|
| product name | `Product.name` (`cart_cubit.dart:6`) | String | **none found** | No |
| price | `Product.price` | double | **none found** (negatives allowed) | No |
| total | `CartState.total` | double (sum of doubles) | — | No |
| item count | `state.items.length` | List length | **unbounded, no pagination** | — |
| recommendation name | `r['name']` from `/recommend` (`cart_page.dart:33`) | dynamic | no contract | **Unchecked, a null crashes `Text`** |
| email / password | `TextField`s (`login_page.dart:38-39`) | String | **no `maxLength`, no validation** | — |
| login token | `data['token']` (`login_page.dart:25`) | dynamic | — | **Unchecked, a null throws** |

## Part 1 — What broke (worst first)

| # | Severity | Field | Worst-case value | What happens | Fix (file:line) |
|---|---|---|---|---|---|
| 1 | Broken | checkout flow | Tap Checkout with the cart as the root route (the real app flow) | `setState() or markNeedsBuild() called during build` is thrown, then `pop()` removes the only route and the user sees a blank screen with no confirmation | Navigate in a `BlocListener` with `listenWhen`, then `pushReplacement` to a success page (`cart_page.dart:22-24`) |
| 2 | Broken | login response | HTTP 400 with an empty body (wrong password, server down) | Unhandled `FormatException: Unexpected end of input`, the spinner runs forever and the Login button never returns | `try/catch/finally`, check `statusCode`, show an inline error, add `mounted` checks (`login_page.dart:18-28`) |
| 3 | Broken | item count | 10 realistic items (Worst fixture) | `RenderFlex overflowed` by **276 px** at 375×812 ×1.0, 640 px at 320 w, 3,936 px at 375 w ×2.0, and even 4 px at 430 w ×1.0. Checkout is pushed off-screen | `ListView.builder` in `Expanded` + pinned `SafeArea` checkout bar (`cart_page.dart:25`) |
| 4 | Broken | item count | 1,000 items (Huge) | Overflows by 55,000–496,000 px at every size, and all 1,000 rows are built at once | Same as #3, plus pagination from the API (`cart_page.dart:27`) |
| 5 | Broken | item list | Add an item while the cart is open | The new item never appears. `add()` mutates `state.items` and re-emits the same instance, which Bloc ignores | `emit(CartState(items: [...state.items, p]))` and an immutable `CartState` (`cart_cubit.dart:20-23`) |
| 6 | Broken | checkout button | Double-tap Checkout | Still enabled 100 ms after the tap, so each tap starts another 2 s checkout (duplicate orders) | `isCheckingOut` in state → `onPressed: null` + spinner (`cart_page.dart:36-39`, `cart_cubit.dart:25`) |
| 7 | Broken | recommendations | `/recommend` returns an error | A spinner that never stops (still there after 5 s). The request is also re-sent on every rebuild | Fetch once in a cubit; on error, hide the section (`cart_page.dart:29-34`) |
| 8 | Broken | email + password | Both empty | Request goes straight to the API, then the same endless spinner as #2 | `Form` + validators, no network call until valid (`login_page.dart:38-42`) |
| 9 | Broken | empty cart | 0 items | Shows "Total: ₹0.0" with Checkout **enabled**. Nothing in the app calls `add()`, so every real user lands here | Empty state with a "Browse products" action; hide or disable Checkout (`cart_page.dart:25-39`) |
| 10 | Ugly | price / total | `0.1 + 0.2` | "Total: ₹0.30000000000000004" | `NumberFormat.currency(locale: 'en_IN', symbol: '₹')`, store money as int paise (`cart_page.dart:27-28`) |
| 11 | Ugly | price | `499` | "₹499.0" | Same as #10 |
| 12 | Ugly | price | `12345678.9` | "₹12345678.9" (no grouping, one decimal) instead of ₹1,23,45,678.90 | Same as #10, plus `FontFeature.tabularFigures()` |
| 13 | Ugly | login button | Text scale ×2.0 | The label fits, but the tap target is a fixed **36 dp** (needs ≥ 48) | `FilledButton` with `minimumSize: Size.fromHeight(48)` (`login_page.dart:41-49`) |
| 14 | Ugly | email field | `bartholomew.fitzgerald+orders@northwind-industries-holdings.example.com` | Default keyboard (no `@`), autocorrect on, no autofill hints | `keyboardType: emailAddress`, `autocorrect: false`, `autofillHints`, `textInputAction` (`login_page.dart:38`) |
| 15 | Ugly | product name | Same product twice (`Kinderwagenregenschutzabdeckung` ×2) | Two identical rows, no quantity | Group by `id` and show a quantity stepper (`cart_page.dart:27`) |
| 16 | Fragile | price | `-50` (coupon line) and `0` (gift wrap) | Rendered as "₹-50.0" and "₹0.0". No validation, and discounts aren't modelled | Separate discount lines; format negatives as "−₹50.00" or show "Free" |
| 17 | Fragile | recommendation name | `{"name": null}` or a missing key | `Text(null)` throws a type error (inferred, not run: the harness can't return a 200 response) | Parse into a typed model with a fallback (`cart_page.dart:33`) |
| 18 | Fragile | login token | 200 response without `token` | `prefs.setString('auth_token', null)` throws a type error (inferred) | Null-check the token, otherwise show an error (`login_page.dart:25`) |
| 19 | Fragile | name, email, price | — | No max length in the model or the form | Add limits that match the backend |

## Part 2 — Decisions for you

- **Long product titles: wrap or clamp?** I recommend `maxLines: 2` with an ellipsis in the cart, and the full title on the product page. Cart rows need to stay scannable.
- **Empty cart: hide or disable Checkout?** I recommend hiding it and showing the empty state's "Browse products" button instead. A disabled primary button with nothing to buy is noise.
- **Recommendations failing: show an error or hide the section?** I recommend hiding it. It's optional content, so a retry button there just competes with Checkout.
- **1,000 items: virtualize or paginate?** `ListView.builder` virtualizes, which fixes the jank. Whether to paginate depends on whether a real cart can get that big; if not, put a sensible cap on the backend.
- **Negative prices: allowed?** If coupons are line items, give them their own type and styling instead of a negative `Product`.

## Part 3 — What held up

- **Login layout:** no overflow in any of the 24 combinations (320 → 1024 wide, ×1.0 → ×2.0, keyboard open or closed), even with the very long email and a `pässwörd 🔐 with spaces` password typed in. The label still fits inside the 36 px bar at ×2.0.
- **Login double-submit guard:** works, because `loading` is set before the first `await`.
- **Cart rows:** no horizontal overflow at any width. `ListTile` handled the Devanagari, Arabic (RTL text), emoji-first, German compound and 120-character titles. Every cart failure was vertical.
- **Demo, One and Empty cart fixtures:** lay out cleanly at every size and scale. The empty case only fails on content (#9), not layout.
- **Worst fixture at 1024×768 ×1.0:** fits, but only just.

---

The switch lives only in tests: `test/stress_test.dart`, with fixtures `demo`, `worst`, `empty`, `one` and `huge` plus the login matrix. Nothing ships in `lib/`. Once fixed, keep the file as regression coverage, and also re-run the Demo fixture so the fixes don't regress the happy path.

Say `fix all` or `fix 1, 3` and I'll apply them.
