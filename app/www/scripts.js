/* Neonicotinoids in Wisconsin Waters: client-side helpers */

// Reduced motion --------------------------------------------------------------

// user's reduced-motion preference, sent to the server as input$reduced_motion
$(document).on("shiny:connected", function () {
  var mq = window.matchMedia("(prefers-reduced-motion: reduce)");
  Shiny.setInputValue("reduced_motion", mq.matches);
  mq.addEventListener("change", function (e) {
    Shiny.setInputValue("reduced_motion", e.matches);
  });
});

// Share links -----------------------------------------------------------------

(function () {
  // On Posit Connect the app runs in an iframe whose path adds a _w_<worker>
  // segment to the content URL. Logged-in users see that page inside a
  // further (same-origin) dashboard frame, so window.top can be the Connect
  // dashboard. Walk up only while the parent is at the same content path.
  function contentPath(win) {
    return win.location.pathname.replace(/_w_[0-9a-f]+\/?$/, "");
  }

  function appWindow() {
    var win = window;
    var path = contentPath(window);
    while (win.parent !== win) {
      try {
        if (contentPath(win.parent) !== path) break;
      } catch (e) {
        break; // cross-origin parent
      }
      win = win.parent;
    }
    return win;
  }

  function baseUrl() {
    var loc = appWindow().location;
    return loc.origin + contentPath(appWindow());
  }

  $(document).on("shiny:connected", function () {
    // strip shared-link parameters from the address bar once applied
    Shiny.addCustomMessageHandler("clear-url", function (x) {
      var w = appWindow();
      if (w.location.search) {
        w.history.replaceState(w.history.state, "", baseUrl() + w.location.hash);
      }
    });

    Shiny.addCustomMessageHandler("share-url", function (query) {
      var el = document.getElementById("share_url");
      if (!el) return;
      el.value = baseUrl() + (query ? "?" + query : "");
      $(el)
        .closest(".modal")
        .one("shown.bs.modal", function () {
          el.select();
        });
    });
  });

  $(document).on("click", "#share_copy", function () {
    var btn = this;
    var el = document.getElementById("share_url");
    var done = function () {
      $(btn).find("span").text("Copied!");
    };
    var fallback = function () {
      el.select();
      if (document.execCommand("copy")) done();
    };
    if (navigator.clipboard) {
      navigator.clipboard.writeText(el.value).then(done, fallback);
    } else {
      fallback();
    }
  });
})();

// Sites table -----------------------------------------------------------------

// site name buttons in the Explore sites table select that site
$(document).on("click", ".site-link", function () {
  Shiny.setInputValue(this.dataset.input, this.dataset.key, {
    priority: "event",
  });
});
