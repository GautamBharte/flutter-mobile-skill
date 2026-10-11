I added a product search screen that uses BLoC. You type in the search box, and the bloc calls `GET $baseUrl/products?q=<query>` 300 ms after you stop typing. If you keep typing while a search is still loading, that older search is cancelled, so an out-of-date response can never replace newer results. `flutter analyze` reports no issues and `flutter test` passes all 16 new tests.

## What I added

```
lib/features/search/
  data/product_search_repository.dart   # HTTP call + JSON parsing, throws ProductSearchException
  bloc/product_search_bloc.dart         # Bloc + debounce/restartable transformer
  bloc/product_search_event.dart        # SearchQueryChanged
  bloc/product_search_state.dart        # status enum + query + products + errorMessage
  view/search_page.dart                 # BlocProvider (creates the bloc)
  view/search_view.dart                 # UI (BlocBuilder): search box + all states
test/features/search/
  product_search_bloc_test.dart         # bloc_test: success, failure, debounce, clear, dedupe, stale-result drop
  product_search_repository_test.dart   # URL/encoding, parsing, 500, bad JSON, network error
  search_view_test.dart                 # typing dispatches events; results / empty / error+retry render
```

**How the pieces connect**
- **Repository:** `main.dart` now wraps the app in `RepositoryProvider(create: (_) => ProductSearchRepository(baseUrl: baseUrl))`. The repository receives `baseUrl` through its constructor rather than importing `main.dart`. It also accepts an `http.Client`, so tests can swap in `MockClient`.
- **Why a Bloc and not a Cubit:** search needs event transformers. `debounce` waits until typing stops, and `restartable` keeps only the latest query. This is the case `build-bloc.md` says calls for a full Bloc.
- **What the screen shows:**
  - before typing: a hint
  - first search: a spinner
  - a new search while results are showing: the old results stay up with a thin progress bar on top, so the list doesn't flicker
  - nothing found: "No products found for …"
  - error: a message and a Retry button
  - otherwise: the results list
  - Clearing the box resets the screen without sending a request.
  - Typing an extra space does not trigger a new request.
- **Search text and encoding:** the query is URL-encoded, so text like `red & blue` is sent correctly.
- **Results and prices:** results reuse your existing `Product` class from `cart_cubit.dart`, so they can later be added to the cart. Prices use the same `₹` format as the cart.
- **Opening the screen:** a 🔍 button in the Cart page's AppBar calls `Navigator.of(context).push(SearchPage.route())`.
- **Native feel:** the box opens with focus, the keyboard shows a Search key, scrolling the list hides the keyboard, the progress indicator is `.adaptive`, and the clear button has a tooltip for screen readers.

## Other changes
- **New packages** (added with `flutter pub add`): `equatable`, `bloc_concurrency`, `stream_transform`, plus `bloc_test` and `mocktail` for tests only.
- **`AndroidManifest.xml`:** added `android.permission.INTERNET`. Your main manifest didn't have it. Debug builds get it automatically, but **release Android builds would fail every network call** without it. That includes search, and also login and recommendations.

## Things you should know or decide
1. **Response format is assumed.** I assumed the API returns either a JSON list or `{"products": [...]}`, where each item has `id`, `name` and `price`. If your API uses different field names, change `_productFromJson` in `product_search_repository.dart`.
2. **🔴 Live secret in the code:** `main.dart` contains a hard-coded `DEMO_SECRET_KEY…` key, and `cart_page.dart` sends it in a URL. Anyone can pull it out of the APK or IPA. Revoke that key and move the call to your backend. Search does not use the key.
3. **Plain `http://` base URL:** `baseUrl` is `http://`, which only works because the app currently allows unencrypted traffic on both platforms (`usesCleartextTraffic` on Android, `NSAllowsArbitraryLoads` on iOS). Switch the API to `https://` before release.
4. **"Add to cart" from search isn't wired up.** `CartCubit.add` changes the existing list in place and then emits the same state object, so the cart screen would never rebuild. Fix it first with `emit(CartState(items: [...state.items, p]))`, then add a cart button to the search result tile.
5. **Lint rules are not running.** `flutter_lints` is in `pubspec.yaml`, but the project has no `analysis_options.yaml`, so `flutter analyze` isn't checking them. That's why the `print` in `login_page.dart` isn't flagged. Add a file containing `include: package:flutter_lints/flutter.yaml` to turn them on.

I only touched the files listed above, plus a small edit to `main.dart` and `cart_page.dart`. I didn't fix the other existing issues, but I can run a full review if you want.
