#!/usr/bin/env bash
# Quick grep-based scan of a Flutter project for common anti-patterns.
# Usage: flutter_scan.sh <project-dir>
# Output is a starting map only — confirm each hit by reading the code.

set -u
ROOT="${1:-.}"
LIB="$ROOT/lib"
[ -d "$LIB" ] || { echo "No lib/ directory under $ROOT"; exit 1; }

section() { printf '\n## %s\n' "$1"; }
hits() { grep -rnE --include='*.dart' "$1" "$LIB" 2>/dev/null | head -n "${2:-40}"; }

section "print() calls (use debugPrint/logger, never log secrets)"
hits '(^|[^A-Za-z_.])print\('

section "Possible hard-coded secrets"
hits '(api[_-]?key|secret|token|password)[A-Za-z_]*\s*[:=]\s*["'"'"'][^"'"'"']{8,}'
hits '(DEMO_SECRET_KEY|AIza[0-9A-Za-z_-]{20,}|ghp_[0-9A-Za-z]{20,})'

section "Cleartext http:// URLs"
hits '["'"'"']http://[^l"'"'"']'

section "Files with await + navigation/dialogs and no mounted check (verify: context after await, or navigation inside build)"
grep -rlE --include='*.dart' 'await ' "$LIB" | while IFS= read -r f; do
  if grep -qE '(Navigator\.|ScaffoldMessenger\.|showDialog|showModalBottomSheet|context\.(go|push|pop))' "$f" \
     && ! grep -qE '(context\.mounted|!mounted|if \(mounted)' "$f"; then
    echo "$f"
  fi
done

section "Controllers created — verify each is disposed"
grep -rlE --include='*.dart' '(TextEditingController|ScrollController|AnimationController|PageController|TabController|FocusNode|StreamSubscription|Timer)\(' "$LIB" | while IFS= read -r f; do
  created=$(grep -cE '(TextEditingController|ScrollController|AnimationController|PageController|TabController|FocusNode)\(' "$f")
  disposed=$(grep -cE '\.(dispose|cancel)\(\)' "$f")
  if [ "$created" -gt "$disposed" ]; then
    echo "$f: created=$created dispose/cancel=$disposed"
  fi
done

section "FutureBuilder with future created inline (refetches every build)"
hits 'future:\s*_?[A-Za-z_.]+\([^)]*\)\s*,'

section "BlocProvider.value with create-like constructor (leak)"
hits 'value:\s*[A-Z][A-Za-z]*(Bloc|Cubit)\('

section "Navigation/dialogs possibly inside a builder (side effects belong in BlocListener)"
hits 'builder:.*(Navigator\.|showDialog|ScaffoldMessenger)'
grep -rnE --include='*.dart' -A6 'BlocBuilder<' "$LIB" 2>/dev/null | grep -E '(Navigator\.|showDialog|ScaffoldMessenger)' | head -n 20

section "Mutating state collections before emit"
hits 'state\.[A-Za-z_]+\.(add|remove|insert|clear|sort)\('

section "SharedPreferences storing tokens (use flutter_secure_storage)"
hits 'set(String)?\(\s*["'"'"'][^"'"'"']*(token|jwt|password)'

section "Non-builder ListView/Column with mapped children"
hits '(children:\s*|\.\.\.)[A-Za-z_.!]+\.map\('

echo
echo "Done. Confirm every hit manually before reporting."
