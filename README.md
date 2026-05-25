# DefaultScheme

Force a preferred app for URL Schemes and Universal Links on jailbroken iOS, with a management app, test entry points, and open logs.

## Project Layout

- `App/`
  The management app. Used to browse rules, edit target apps, test open behavior, and inspect open logs.
- `Tweak/`
  System-side hooks and routing logic. It currently injects into `lsd` and `SpringBoard`.
- `Shared/`
  Shared config models and rule parsing used by the app, tweak, and helper tool.
- `Helper/`
  The `defaultschemectl` command-line tool for reading and writing rules, probing routing behavior, and generating the config mirror.
- `DefaultSchemeTweak.plist`
  The tweak filter. It currently injects only into:
  - `SpringBoard`
  - `lsd`
  - `DefaultScheme`

## How It Works

- URL Scheme and Universal Link target rewriting primarily happens in the LaunchServices path, covering key entry points such as `LSAppLink`, `_LSDOpenClient`, and `LSApplicationWorkspace`.
- `SpringBoard` keeps fallback hooks for requests that have already entered the foreground dispatch stage.
- When a Universal Link rule matches, the original URL is preserved and only the final target app is replaced.
- Open logs are recorded on the system side; the management app only displays them.

## Config Storage

Primary config file:

`/private/var/mobile/Library/Preferences/codes.var.tweak.defaultscheme.plist`

Config mirror filename:

`DefaultSchemeConfig.plist`

The mirror is synced to a tweak-visible location so `lsd` and `SpringBoard` can still read configuration when direct preference access is unavailable.

The current config contains three parts:

```plist
{
  schemes = {
    weixin = "com.tencent.xin";
  };
  hosts = {
    "www.youtube.com" = "com.google.ios.youtube";
  };
  links = (
    {
      host = "link.example.com";
      pathMatcher = "/invite/*";
      bundleID = "com.example.targetapp";
      hostWildcard = 0;
      sourceHint = "configured";
      identityVersion = 1;
      patternKind = "path";
    }
  );
}
```

Notes:

- `schemes`
  Routes by URL scheme.
- `hosts`
  Routes by Universal Link host as a host-only fallback.
- `links`
  Routes by more precise link rules and takes precedence over `hosts`.
- `bundleID = "__NO_APP__"`
  Means block the open request instead of handing it to any app.

## Management App

After installation, the `DefaultScheme` app provides:

- `Schemes`
  Browse and edit default targets for URL Schemes.
- `Links`
  Browse and edit Universal Link rules, including both host-only and path/query-level rules.
- `Test`
  Directly test URL opening behavior.
- `Log`
  View recent open logs including source, target, URL, type, and timestamp.
- `Incoming Link`
  External links routed to DefaultScheme display the complete original link in a dedicated view.

## Incoming Links

The app registers the `defaultscheme` URL scheme. Opening any link with that scheme, such as:

```text
defaultscheme://show?link=https%3A%2F%2Fexample.com%2Fpath%3Fq%3D1
```

launches DefaultScheme and presents a standalone view containing the complete link. The view also offers copy and test actions.

`DefaultScheme` is also available as a target in the `Schemes` and `Links` rule pickers. Configure either a URL scheme or a Universal Link rule to DefaultScheme, and external opens of that URL will launch the DefaultScheme app and show the complete original URL in the same dedicated view.

Both custom-scheme opens and Universal Link handoff are handled by the app. Universal Links use `NSUserActivity.webpageURL`, so the page receives the complete original `http`/`https` URL rather than a wrapped `defaultscheme` URL.

From the incoming link view, tap `Open With` to choose any app that originally registered the same scheme or link. Selecting an app opens it directly with the same URL. If only one original candidate is available, it opens immediately.

Open With uses the foreground `UIApplication` open path and passes the selected target to the injected LaunchServices hooks. This keeps the original URL in the final app handoff for both custom schemes and Universal Links; private `LSApplicationWorkspace`/`LSAppLink` calls are intentionally avoided because they fail with `-50`/`-54` from the DefaultScheme process.

Candidate discovery uses `LSApplicationWorkspace`'s original registration data, and DefaultScheme itself is excluded from the list. For Universal Links, `applicationsAvailableForOpeningURL:` often returns Safari even when other apps have associated-domain entitlements, so DefaultScheme also uses the Shared Web Credentials system link rules to enumerate the apps that really registered the URL. Safari is not treated as an original Universal Link candidate.

After saving rules, the app syncs the config mirror and restarts `lsd` so the main routing path picks up changes quickly.

## Command Line

`/usr/bin/defaultschemectl` is still provided.

Currently available commands:

```sh
defaultschemectl list
defaultschemectl sync-route-config-mirror
defaultschemectl set-scheme weixin com.tencent.xin
defaultschemectl set-host www.youtube.com com.google.ios.youtube
defaultschemectl set-link link.example.com /invite/* com.example.targetapp
defaultschemectl set-link-rich rule-id link.example.com /invite/* - com.example.targetapp
defaultschemectl del-scheme weixin
defaultschemectl del-host www.youtube.com
defaultschemectl del-link link.example.com /invite/*
defaultschemectl del-link-rich rule-id link.example.com /invite/* -
defaultschemectl probe-url weixin://scanqrcode
defaultschemectl open-url weixin://scanqrcode
defaultschemectl perform-open-url com.tencent.xin weixin://scanqrcode
defaultschemectl trace-url weixin://scanqrcode
defaultschemectl inspect-applink https://link.example.com/invite/abc
defaultschemectl inspect-swc https://link.example.com/invite/abc
defaultschemectl inspect-method LSApplicationWorkspace URLOverrideForURL:
defaultschemectl list-methods LSApplicationWorkspace
defaultschemectl list-classes LS
```

The `path-matcher` argument of `set-link` is still backward compatible:

- No `*`
  Exact match
- A single trailing `*`
  Prefix match
- `*` in the middle or in multiple places
  Wildcard match

For full-featured link rules, prefer `set-link-rich`, which maps to structured fields such as `ruleID`, `pathMatcher`, `queryMatcher`, and `hostWildcard`.

## Build

The current `Makefile` defaults to:

- `THEOS_PACKAGE_SCHEME ?= roothide`
- `.DEFAULT_GOAL := package-roothide`

So running:

```sh
make
```

is equivalent to:

```sh
make package-roothide
```

Other targets:

```sh
make package-rootless
make package-rootful
make install-roothide
```

## roothide Notes

- roothide 包默认只构建 `arm64e`
- 打包时会附带 roothide patch 与 pkgmirror 布局
- 当前开发流程默认以 roothide 为主

## rootless Notes

- `make package-rootless` 会默认连续产出两个 rootless 包：`iphoneos-arm64` 和 `iphoneos-arm64e`
- `iphoneos-arm64` 包只编译 `arm64`，`iphoneos-arm64e` 包只编译 `arm64e`
- 如果需要 roothide 专用布局，使用 `make package-roothide`

## Related Files

- [Makefile](Makefile)
  Default roothide packaging and install targets.
- [DefaultSchemeTweak.plist](DefaultSchemeTweak.plist)
  The tweak filter.
- [Shared/DSRoutingConfig.m](Shared/DSRoutingConfig.m)
  Config read/write, rule normalization, SWC snapshots, and open log persistence.
- [Tweak/DSRouteSupport.m](Tweak/DSRouteSupport.m)
  Route snapshots and URL-to-bundleID decisions.
- [Tweak/DSObjectExtraction.m](Tweak/DSObjectExtraction.m)
  Extracts URLs and schemes from LaunchServices and SpringBoard private objects.
- [Tweak/DSOpenLogging.m](Tweak/DSOpenLogging.m)
  System-side open log recording and relay.
