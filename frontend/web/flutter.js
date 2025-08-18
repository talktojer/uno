// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This file is used to load the Flutter engine and initialize the app.
// It is loaded by the web/index.html file.

(function() {
  'use strict';

  // Flutter web loader configuration
  var serviceWorkerVersion = null;
  var scriptLoaded = false;

  function loadMainDartJs() {
    if (scriptLoaded) {
      return;
    }
    scriptLoaded = true;
    var scriptTag = document.createElement('script');
    scriptTag.src = 'main.dart.js';
    scriptTag.type = 'application/javascript';
    document.body.appendChild(scriptTag);
  }

  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function () {
      var serviceWorkerUrl = 'flutter_service_worker.js?v=' + serviceWorkerVersion;
      navigator.serviceWorker.register(serviceWorkerUrl)
        .then((reg) => {
          function waitForActivation(serviceWorker) {
            serviceWorker.addEventListener('statechange', () => {
              if (serviceWorker.state == 'activated') {
                console.log('Installed new service worker.');
                loadMainDartJs();
              }
            });
          }
          if (!reg.active && (reg.installing || reg.waiting)) {
            var serviceWorker = reg.installing || reg.waiting;
            waitForActivation(serviceWorker);
            serviceWorker.addEventListener('statechange', (e) => {
              if (e.target.state == 'activated') {
                loadMainDartJs();
              }
            });
          } else if (!reg.active.scriptURL.endsWith(serviceWorkerVersion)) {
            console.log('New service worker is available.');
            if (confirm('A new version of this app is available. Reload to update?')) {
              window.location.reload();
            }
          } else {
            loadMainDartJs();
          }
        });

      // If service worker doesn't succeed in a reasonable amount of time,
      // fallback to plain <script> tag.
      setTimeout(() => {
        if (!scriptLoaded) {
          console.warn('Failed to load app from service worker. Falling back to plain <script> tag.');
          loadMainDartJs();
        }
      }, 4000);
    });
  } else {
    loadMainDartJs();
  }
})();

