I've added a product search screen. The cart page now has a search icon in its app bar. Tapping it opens a screen where you type in a search box, and results load from `GET $baseUrl/products?q=…`. Each result has an add-to-cart button. `flutter analyze` finds no issues and all 9 tests pass.

## Before you ship: two problems with existing code

These were already in the app. I didn't change them because they're outside this task, but the search feature makes them more pressing.

1. **A live secret key is hardcoded in `lib/main.dart`** (`apiKey = 'DEMO_SECRET_KEY…'`). Anyone who has the app can pull it out of the binary, and `cart_page.dart` also sends it in a URL. Revoke the key now, take it out of the app, and move whatever needs it to your backend. The search screen doesn't use it.
2. **`baseUrl` uses `http://`, not `https://`.** Cleartext traffic is also turned on (`usesCleartextTraffic` on Android, `NSAllowsArbitraryLoads` on iOS). That means search queries, the login password and the auth token all travel unencrypted. Switch to `https://` and remove both of those settings.

## How the search works

- **Uses Bloc, like the rest of the app.** It has two events: the query changed, and retry. Its state tracks the status (`initial`, `loading`, `success`, `failure`), the query and the results.
- **Waits for typing to pause.** It sends a request 300 ms after the last keystroke, not on every key.
- **Drops outdated results.** A new query cancels the one still loading, so a slow older response can't replace newer results.
- **Covers every screen state:** a prompt before you type, a loading spinner, a thin progress bar over the old results while a new search loads, "No products match …", and an error message with a Retry button.
- **Handles bad responses safely.** It checks the HTTP status, gives up after 10 seconds, and skips any result that is missing its id, name or price.
- **No new packages.** The two small helpers that handle the typing pause and the cancelling live in `search_bloc.dart`. If you'd rather use packages, `bloc_concurrency` and `rxdart` do the same job.

### An assumption to check
I didn't know what the response looks like. The code accepts either a plain list or `{"products": [...]}`, where each item is `{id, name, price}`. `price` can be a number or a string. If your API is different, change `ProductSearchRepository.search` to match.

## Files

**New**
- `lib/features/search/data/product_search_repository.dart`: makes the request and reads the response. You can pass in your own `http.Client` for tests.
- `lib/features/search/bloc/search_bloc.dart`: the events, the state and the Bloc.
- `lib/features/search/view/search_page.dart`: the screen.
- `test/features/search/search_bloc_test.dart`: tests for the request format, both response shapes, HTTP errors, the typing pause, outdated results being dropped, empty queries, and failure then retry.
- `test/features/search/search_page_test.dart`: tests that typing shows results, that add-to-cart updates the cart, and the "no match" message.

**Changed**
- `lib/features/cart/view/cart_page.dart`: added the search icon.
- `lib/features/cart/cubit/cart_cubit.dart`: **I fixed a bug in `add()`.** It changed the existing cart state and sent the same object again. Bloc ignores that, so the cart screen never updated. It now sends a new state with the item added. Without this fix, adding from search would look like it did nothing.

## Other problems I saw but didn't touch
- `CartPage` calls `Navigator.pop` inside `BlocBuilder` when checkout finishes, which runs during a screen rebuild. That belongs in a `BlocListener`.
- `CartPage` reloads recommendations every time it rebuilds, because the request is started inside `build`.
- In `main.dart`, `BlocProvider.value(value: CartCubit())` creates the cubit but never closes it. It should be `BlocProvider(create: ...)`.
- `LoginPage` prints the login response, token included, to the log. It also doesn't handle errors, and it uses `context` after an `await` without checking `mounted`.
