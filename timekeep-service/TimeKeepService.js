/* -*- indent-tabs-mode: nil; js-indent-level: 2 -*- */
/* vim: set shiftwidth=2 tabstop=2 autoindent cindent expandtab: */

/**
 * Copyright 2015 Mozilla Foundation and Mozilla contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

"use strict";

const {classes: Cc, interfaces: Ci, utils: Cu, results: Cr} = Components;

Cu.import("resource://gre/modules/XPCOMUtils.jsm");
Cu.import("resource://gre/modules/Services.jsm");
Cu.import("resource://gre/modules/ctypes.jsm");
Cu.import("resource://gre/modules/systemlibs.js");
Cu.import("resource://gre/modules/osfile.jsm");

const TIMEKEEPSERVICE_CID = Components.ID("{f2c71065-45f0-4387-8c0c-f2de807d70c0}");
const TIMEKEEPSERVICE_CONTRACTID         = "@mozilla.org/timekeep-service;1";

const kXpcomShutdownObserverTopic        = "xpcom-shutdown";
const kSysClockChangeObserverTopic       = "system-clock-change";
const kTimeAdjustProperty                = "persist.sys.timeadjust";
const kRtcSinceEpoch                     = "/sys/class/rtc/rtc0/since_epoch";

function log(msg) {
  dump("-*- TimeKeepService: " + msg + "\n");
}

function TimeKeepService() {
  log("B2G time service enabled");
  Services.obs.addObserver(this, kXpcomShutdownObserverTopic, false);
  Services.obs.addObserver(this, kSysClockChangeObserverTopic, false);
}

TimeKeepService.prototype = {
  classID: TIMEKEEPSERVICE_CID,
  QueryInterface: XPCOMUtils.generateQI([Ci.nsIObserver]),
  classInfo: XPCOMUtils.generateCI({
    classID: TIMEKEEPSERVICE_CID,
    contractID: TIMEKEEPSERVICE_CONTRACTID,
    interfaces: [Ci.nsIObserver],
    classDescription: "B2G TimeKeep Service",
  }),

  readEpoch: function() {
    try {
      log("Opening " + kRtcSinceEpoch);
      return OS.File.open(kRtcSinceEpoch, { read: true, write: false, append: false }).then(file => {
        return file.read(32).then(bytes => {
          let decoded = parseInt((new TextDecoder()).decode(bytes));
          file.close();
          return Promise.resolve(decoded);
        });
      });
    } catch (ex) {
      log("Error reading " + kRtcSinceEpoch + ": " + ex);
      return Promise.reject(ex);
    }
  },

  updateAdjust: function(now) {
    log("Received time update: " + now);
    let seconds = now / 1000;

    log("Reading epoch from " + kRtcSinceEpoch);
    this.readEpoch().then(epochSince => {
      log("Read epoch_since=" + epochSince);
      // Forcing a string for property_set();
      let newAdjust = "" + Math.floor(seconds - epochSince);
      log("Setting " + kTimeAdjustProperty + "=" + newAdjust);
      libcutils.property_set(kTimeAdjustProperty, newAdjust);
    });
  },

  observe: function(subject, topic, data) {
    switch (topic) {
      case kXpcomShutdownObserverTopic:
        Services.obs.removeObserver(this, kXpcomShutdownObserverTopic);
        Services.obs.removeObserver(this, kSysClockChangeObserverTopic);
        break;

      case kSysClockChangeObserverTopic:
        this.updateAdjust(Date.now());
    }
  },
};

this.NSGetFactory = XPCOMUtils.generateNSGetFactory([TimeKeepService]);
