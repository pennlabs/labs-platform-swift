<a id="readme-top"></a>
<br />
<div align="center">
  <a href="https://pennlabs.org>
    <img src="images/logo.png" alt="Logo" width="80" height="80">
  </a>

<h3 align="center">LabsPlatformSwift</h3>

  <p align="center">
    A Swift package designed to interface with the Penn Labs Platform
  </p>
</div>



<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
        <li><a href="#setup">Setup</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <ul>
        <li><a href="#network-requests">Network Requests</a></li>
        <li><a href="#analytics">Analytics</a></li>
      </ul>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contact">Contact</a></li>
  </ol>
</details>



<!-- ABOUT THE PROJECT -->
# About The Project

This project was built using Swift, and was designed to take some complexity out of authentication and analytics for Swift-based Penn Labs products (Penn Mobile).

It has very few functions and views publicly-exposed (usable by the developer). This is intentional. While exposing more functions is certainly a possibility, this decision was made to make the library simple to understand and use.

**Note: all of the public functions have DocC documentation provided. Use these docs as a reference in the event of confusion.**

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- GETTING STARTED -->
# Getting Started

You can add this package to any Swift project (provided you have a valid Client ID issues by the Penn Labs Platform)

## Prerequisites

This library works only for iOS >16.0 projects. Mac support may be added in the future.

## Installation

1. Obtain a Client ID and Redirect URL from Penn Labs Platform.
2. Add the package using the Swift Package Browser by clicking File>>Add Package Dependencies. Then paste the URL for this Github repository.

## Setup

1. With a new project, add the `.enableLabsPlatform` modifier to the root view. You will need to provide a few details.
- `analyticsRoot: String`: The root keypath for analytics tokens. For example, in Penn Mobile, all analytics values will look like `pennmobile.{FEATURE}.{SUBFEATURE}`. In that case, the `analyticsRoot = "pennmobile"`
- `clientId: String` and `redirectUrl: String`. These are issued by Platform.
- `loginHandler: (Bool) async -> Void`: This function is run on startup and when the login state changes. The boolean argument is `true` when the user is logged in, `false` otherwise.
- `defaultLoginHandler: () -> Void`: The App Store requires a default login for most apps (for App Store verification purposes). This function will run if the default login credentials are intercepted by the login WebView.




<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- USAGE EXAMPLES -->
# Usage

**NOTE: The `LabsPlatform.shared` object is not meant to be regularly accessed (only for login state prompts, see below). Hence, it has few exposed functions.** 

1. At some point in your application, you will need to prompt `LabsPlatform` to log-in with the Penn Labs Platform. You can access the singleton object `LabsPlatform.shared` to prompt log-in.
2. Note that this object is optional, so you must handle the potential nil value (the event that Platform fails to enable).

Use the following example code to get started:

```swift
import LabsPlatformSwift

Button {
    LabsPlatform.shared?.loginWithPlatform()
} label: {
    Text("Click here to log in.")
}
```

When the button is pressed, a WebView sheet should appear, prompting a log-in using the Penn Duo gateway. Note that when the login completes, the WebView sheet will close and the app will run the `loginHandler` function provided in the root view.

3. Similarly, the `LabsPlatform.shared` object has a logout method `LabsPlatform.logoutPlatform`. You can use this function in a similar manner as above. Akin to `loginWithPlatform`, this function will always run `loginHandler(false)`.

4. The login will be cached and automatically refreshes. Note: if the refresh request fails due to server error, the user will be logged out. However, if the refresh request fails due to network, it is assumed that the refresh token is still valid, so the user will stay logged in, but this network error will be passed to the callee.

## Network Requests

There are a few ways to approach network requests using this library. An important factor is the endpoint: Swift `URLRequest` often does not retain authorization headers if the network request is redirected. Hence, the package provides two ways of approaching authenticated network requests.

### Aside
For both methods, the user has the option to choose between two `PlatformAuthMode`s: `.jwt` and `.accessToken`. These are used by the various Penn Labs services. In most cases, a developer may opt to use the `.accessToken` (since this token is supported by most Penn Labs Mobile Backend services). However, there are some services (like Analytics) that require a JWT (JSON Web Token).

While Analytics, for example, is handled natively by this library, access to both kinds of tokens is given. 

**Note: Don't use the following methods for non-Penn Labs products. Doing so will expose sensitive access tokens or JSON Web Tokens to unauthorized sites.**

### Method 1: URLRequest
The package provides an extension to the `Foundation.URLRequest` class. You can access it as follows:

```swift
// replace with your URL
let url = URL(string: "https://platform.pennlabs.org/accounts/me/")! 

var request: URLRequest = try await URLRequest(url: url, mode: PlatformAuthMode.jwt)
```

Note that this initializer is both asynchronous and throwing. It is asynchronous because it fetches a refreshed token prior to returning the `URLRequest` object. It is throwing because the user may not be logged in, Platform may not be enabled, or other issues may arise that prevent the creation of an authenticated `URLRequest`. Hence, another way of handling this is as follows (more code is provided, for reference, since this is the intended use)

```swift
func getMyIdentity() async -> Identity? {
    let url = URL(string: "https://platform.pennlabs.org/accounts/me/")!
    guard let request = try? await URLRequest(url: url, mode: PlatformAuthMode.jwt) else {
        return nil
    }

    guard let (data, response) = try? await URLSession.data(for: request),
        let httpResponse = response as? HTTPURLResponse,
        httpResponse.statusCode == 200 else {
            return nil
        }

    return try? JSONDecoder().decode(Identity.self, from: data)
}
```

Note that errors in this implementation go unnoticed because of the `try?` keyword, but an implementation using a throwing function could just as easily be made.

Under the hood, this initializer provides the relevant authorization token (either JWT or Access Token) as the `Authorization` and `X-Authorization` headers. However, as stated previously, Swift URLSession does not retain these headers in the event of a redirect, which motivates the second method.

### Method 2: URLSession
The package provides an extension to the `Foundation.URLSession` class. You can access it as follows:

```swift
// This has an optional config parameter that defaults to URLSessionConfiguration.default, but can be overridden.
var session: URLSession = try await URLSession(mode: .jwt)

```

Similar to the previous method, this method is asynchronous and throwing for the same reasons. This particular initializer overrides the `additionalHTTPHeaders` field of the `URLSession` class. See an entire example below.

```swift
func getMyIdentity() async -> Identity? {
    // replace with your URL
    let url = URL(string: "https://platform.pennlabs.org/accounts/me/")! 

    guard let session = try? await URLSession(mode: .jwt) else {
        return nil
    }

    guard let (data, response) = session.data(for: url),
        let httpResponse = response as? HTTPURLResponse,
        httpResponse.statusCode == 200 else {
            return nil
        }

    return try? JSONDecoder().decode(Identity.self, from: data)
}
```

These are the only two ways of authenticating a URL request using this Platform library. The design is kept fairly restrictive for two reasons:
1. It *somewhat* protects our API Keys (I actually don't know how but it sounds true), and more importantly;
2. It encourages our developers to use the async/await philosophy for network requests, which will lead to a more consistent and readable codebase in the future.

## Analytics

### Motivation

A large motivation for the project was to implement easy-to-use analytics into our Swift products. 

Analytics are incredibly valuable when making design or roadmap decisions. Given enough time and data, analytics allow developer to understand points of **friction** in their applications, perform **A/B testing** (not implemented...yet?), and otherwise better understand the **user experience** in a quantifiable way.

*Side note: this library was originally designed solely for the brand new Penn Labs Analytics API, but upon realizing it requires JWT for verification, the package's objective was widened to support general authentication as well.*

The library was designed to make logging analytics simple, especially in SwiftUI-based View Hierarchies. However, there are other ways to log analytics that can be done in non SwiftUI-based contexts.

### SwiftUI Analytics Logging

Given an analytics key: `pennmobile.dining.kcech.breakfast.appear`, it is easy to understand the general structure. Different paths are separated by `.`, enabling an easy understanding of the exact hierarchy that led to the given key.

The SwiftUI analytics logging aspect of this package was designed with that philosophy in mind.

#### View-Based Logging
Remember that when we initialized our platform object using `enableLabsPlatform`, we provided an `analyticsRoot`. This (under the hood) placed that key in the environment for children views. Consider the following SwiftUI code:

```swift
struct RootView: View {
    @State var loggedIn = false
    var body: some View {
        Group {
            if !loggedIn {
                Button {
                    LabsPlatform.shared?.loginWithPlatform()
                }
            } else {
                ChildView()
            }
        }
        .enableLabsPlatform(analyticsRoot: "testing",
                            clientId: "{ID HERE}",
                            redirectUrl: "{REDIRECT HERE}") { loggedIn in
            self.loggedIn = loggedIn
        }
    }
}

```

We can understand that this view prompts the user to log in if they are not logged in. If they are logged in, it shows `ChildView`. There are many use cases where we would like to have a specific analytics keypath for child view (say, if we instead presented a navigation stack where each screen would have its own keypath).

We can provide `ChildView` with its own analytics keypath using the `View.analytics(subkey: String, logViewAppearances: Bool)` view modifier. `logViewAppearances` is a property that will automatically log `.appear` and `.disappear` analytics values when that view appears and disappears, respectively.

Under the hood, the library provides the view with `.onAppear()` and `onDisappear()` modifiers, but this complexity is abstracted away from an individual view hierarchy.

Therefore, in our example from above, if we provide `ChildView` with the following modifier:

```swift
ChildView()
    .analytics(subkey: "child", logViewAppearances: true)
```

`ChildView` and all its children are in the analytics keypath `testing.child`. We can stack this modifier infinitely as we move down the view hierarchy. For example, `ChildView` could consist of a subview that we wish to label. We could use `.analytics` on this view and give its descendent views their own unique keypaths descending from `testing.child`.

Further, in our example above, we can see that `logViewAppearances = true`. This means that when `ChildView` appears, the analytics library will automatically record a `testing.child.appear` and `testing.child.disappear` value whenever the view appears or disappears on screen, respectively.

This is the core of the view hierarchy aspect of this library. However, while view-based appear/disappear is crucial to data-driven development, there are other needs to log analytics based on certain events.

#### Event-based Logging
Event-based logging follows closely with view-based logging in that it utilizes the same view hierarchy when classifying analytics keypaths. However, event-based logging differs from view-based logging in its usage. Consider the case where we (the developer) wish to log when a user presses a button. This is not a problem that can be solved with view-based logging.

Consider the following code:


```swift
// Say this view has a path: testing.childview.view1.arbitrarilydeepview
struct ArbitrarilyDeepView: View {
    var body: some View {
        Button {
            viewModel.action()
        } label: {
            Text("Click me!")
        }
    }
}
```

In this view, we have a button that we might wish to record presses by the user. Introducing `AnalyticsContextProvider`. This is a view wrapper that provides an `AnalyticsContext` object. See the following example.

```swift
// Say this view has a path: testing.childview.view1.arbitrarilydeepview
struct ArbitrarilyDeepView: View {
    var body: some View {
        AnalyticsContextProvider { context in
            Button {
                viewModel.action()
            } label: {
                Text("Click me!")
            }
        }
    }
}
```

We can now use the `AnalyticsContext.logEvent(key: String, value: String = "1")` function. Note the `value` field. While we can provide a value other than 1, consider that the greatest benefit of analytics is the large amounts of data. That is, using non-numeric values (despite this field being a string) may make this data harder to process down the line, but this is a case left fairly unrestricted since future use cases may vary.

```swift
// Say this view has a path: testing.childview.view1.arbitrarilydeepview
struct ArbitrarilyDeepView: View {
    var body: some View {
        AnalyticsContextProvider { context in
            Button {
                viewModel.action()
                context.logEvent(key: "buttonPressed")
            } label: {
                Text("Click me!")
            }
        }
    }
}
```

By using this function, the library will record, given our current hierarchy, a `testing.childview.view1.arbitrarilydeepview.event.buttonPressed` key with a value of `"1"`. While this keypath may seem long, it is trivial for a SQL query to parse, and it is easy for us as the developer to understand *exactly* how a given event took place, given its hierarchy.

This is an important distinction. The `.analytics` view modifier is used to add additional sections to the keypath (parsed by `.`), and the `AnalyticsContext` object is used to record event-based analytics.

There is one more use case for analytics that this library natively supports. Time-based analytics and operations.

### Time-based Analytics Logging
Time-based analytics logging is valuable in determining how *long* something takes. This could be a certain process, a network request, or anything really. In the case of Penn Mobile, a great motivation for time-based analytics logging is, for example, how long a user takes to book a Group Study Room (GSR) from the moment they click the tab, to the moment their booking is confirmed. This is valuable data that could provide insight into friction or other UX problems. This library provides two main ways of logging time-based analytics: timed operations, and timed tasks.

#### Timed Operations
For timed operations, we can once again use our `AnalyticsContext` object, obtained using the `AnalyticsContextProvider` view wrapper. Let's outline the general process:
- From a given view, we can start an operation, which will log the start time.
- Think of this operation as a ticking stopwatch. It can be stopped at any time, at which point the difference between the start time and end time will be recorded.
- Importantly, an operation can be started in one view and ended/finished in another, **provided that the view that completes the operation is either the same view or a subview of the view that started the operation**.

Let's look at an example.

```swift
// keypath: testing.operationview
struct OperationView: View {
    var body: some View {
        AnalyticsContextProvider { context in
            VStack {
                Button("Start!") {
                    context.beginTimedOperation(operation: "testing")
                }
                Button("End!") {
                    context.finishTimedOperation(operation: "testing")
                }
            }
        }
    }
}
```

Here, we notice that we're using the `AnalyticsContext.beginTimedOperation` and `AnalyticsContext.finishTimedOperation` functions. These functions start and end an operation, respectively.

Note: the full signature of `beginTimedOperation` function is
```swift
AnalyticsContext.beginTimedOperation(operation: String, cancelOnScenePhase: [ScenePhase] = [.background, .inactive])
```
By default, operations are told to cancel whenever the user changes apps, closes the app, or puts their phone to sleep (`ScenePhase.background` and `ScenePhase.inactive`). Though, this behavior can be modified to fit a given use case, depending on the operation.

Under the hood, these two functions create and complete a `AnalyticsTimedOperation` object, whose identifier is `testing.operationview.operation.testing` (that is, `operation.{NAME OF OPERATION}` is appended to the current analytics path).

How would we modify operations across views? Consider the following example.

```swift
// keypath: testing.operationview
struct OperationView: View {
    var body: some View {
        AnalyticsContextProvider { context in
            VStack {
                Button("Start!") {
                    context.beginTimedOperation(operation: "testing")
                }
                SubView()
                    .analytics(subkey: "subview", logViewAppearances: false)
            }
        }
    }
}

// keypath: testing.operationview.subview
struct SubView: View {
    var body: some View {
        AnalyticsContextProvider { context in
            Button("End") {
                context.finishTimedOperation(operation: "testing")
            }
        }
    }
}

```
Wait, does this work? Yes.

*(note: in this example, we chose to give our `SubView` a unique keypath, which in many cases will be the trivial choice. However, we *could* have chosen to not use the `.analytics` modifier. This would make `SubView` have the same path as its parent)*

The `finishTimedOperation` function is designed to search its way up the view hierarchy for operations matching the name given. In other words, it will search:
- `testing.operationview.subview.operation.testing` - this operation doesn't exist
- `testing.operationview.operation.testing` - we've found our operation

With this logic, it is trivial that we can start operations in parent views and end them in children, provided that the **keypaths** present a logical hierarchy.

After a timed operation is finished. The "stopwatch" is stopped and the time is logged as a normal analytics value (where the `key` is the original keypath of the operation and the `value` is the amount of time, in **milliseconds**)

#### Timed Tasks

Our final use case is timed tasks. This is fairly trivial, but has a slight consideration.

The library presents a `Task.timedAnalyticsOperation` static function, whose full signature is: 

```swift
Task.timedAnalyticsOperation(operation: String, cancelOnScenePhase: [ScenePhase] = [.background, inactive]) {
    //function
}
```

This is similar to our `AnalyticsContext.beginTimedOperation` function.

Consider the following usage, using our very own authenticated web requests.

```swift
func updateIdentity() {
    Task.timedAnalyticsOperation(operation: "fetchIdentity") {
        let url = URL(string: "https://platform.pennlabs.org/accounts/me/")!
        guard let request = try? await URLRequest(url: url, mode: PlatformAuthMode.jwt),
            let (data, response) = try? await URLSession.data(for: request),
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200 else {
                viewModel.setIdentity(nil)
            }
       viewModel.setIdentity(try? JSONDecoder().decode(Identity.self, from: data))
    }
}
```

By using `timedAnalyticsOperation`, the library creates an operation, runs the given task, then ends the operation and logs the total running time. This can be valuable in assessing loading times.

The consideration is that because tasks do not take place in the view hierarchy, these operations will be labeled `global.operation.{NAME}`. Duplicate operation names have not been tested.

### Analytics Wrap-Up

The analytics values we've worked hard to record are cached between app launches. This is to prevent unsent values from being lost if a user closes the app.

As for regular use cases, the analytics values are kept in a queue, which is flushed, by default, every 30 seconds. This can be modified by changing the static property: `LabsPlatform.Analytics.pushInterval`. Note that this property should be changed before `enableLabsPlatform` is run, since initializing Platform starts the DispatchQueue on a set interval (which cannot then be changed).

Another property that can be changed is `LabsPlatform.Analytics.expireInterval`. By default, this value is set to `604800` seconds (7 days). On app launches, values created more than this interval ago are pruned from the queue. This is to prevent a backlog of analytics values in the event that there is a failure in some process.

Various endpoints can also be changed throughout the library.

All values should be changed prior to running `enableLabsPlatform`, since some values (like `pushInterval` or `expireInterval`) are relevant as the `LabsPlatform` object is being initialized. That is, these values should be changed in the initializer for whichever struct/class is running `enableLabsPlatform`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ROADMAP -->
## Roadmap

- [ ] Bug fixes to improve stability
- [ ] A/B Testing
- [ ] Phased login
    - The ability to log into multiple OAuth endpoints in a single auth flow, in order to take advantage of cookies when logging in.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Top contributors:

<a href="https://github.com/pennlabs/labs-platform-swift/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=pennlabs/labs-platform-swift" alt="contrib.rocks image" />
</a>

<!-- CONTACT -->
## Contact

- Jonathan Melitski - [GitHub](https://github.com/jonathanmelitski) - [Email](mailto:melitski@sas.upenn.edu)
- Penn Labs - [GitHub](https://github.com/pennlabs) - [Website](https://pennlabs.org)

Project Link: [https://github.com/pennlabs/labs-platform-swift](https://github.com/pennlabs/labs-platform-swift)

<p align="right">(<a href="#readme-top">back to top</a>)</p>
