function everything() {

  var availableSections = ko.observableArray(['global', 'culture', 'lifeandstyle', 'technology', 'sport']);

  function hookContent(bundle, content) {
    var bundleId = bundle.id();
    content.removeContent = function() {
      console.log("remove")
      var removeRequest = reqwest({
        url: '/api/bundles/'+bundleId+'/'+this.id(),
        method: 'delete',
        type: 'json'
      });
      removeRequest.then(function() {
        console.log("ok", arguments)
        bundle.content.remove(this);
        // FIXME: broken
      }.bind(this), function() {
        console.log("error", arguments)
      });
    };
  }

  function hookBundle(bundle) {
    var bundleId = bundle.id();

    for (var i = 0; i < bundle.content().length; i++) {
      hookContent(bundle, bundle.content()[i]);
    }

    if (!bundle.background_uri) {
      bundle.background_uri = ko.observable();
    }
    bundle.background_uri.subscribe(function(newUri) {
      reqwest({
        url: '/api/bundles/'+bundleId,
        method: 'patch',
        type: 'json',
        data: {background_uri: newUri}
      });
    });

    if (!bundle.section) {
      bundle.section = ko.observableArray();
    } else {
      bundle.section = ko.observableArray([bundle.section()]);
    }
    bundle.section.subscribe(function(newSections) {
      var newSection = newSections[0];
      reqwest({
        url: '/api/bundles/'+bundleId,
        method: 'patch',
        type: 'json',
        data: {section: newSection}
      });
    });

    bundle.addUrlInput = ko.observable();
    bundle.addContent = function() {
      var url = this.addUrlInput();
      var id = url.replace('http://www.guardian.co.uk/', '').replace('http://m.guardian.co.uk/', '');
      var addRequest = reqwest({
        url: '/api/bundles/'+bundleId+'/content',
        method: 'post',
        type: 'json',
        data: {id: id}
      });
      addRequest.then(function(response) {
        console.log("ok", arguments)
        var content = ko.mapping.fromJS(response.data);
        hookContent(bundle, content);
        this.content.push(content);
        this.addUrlInput(""); // reset input
      }.bind(this), function() {
        console.log("error", arguments)
      })
    };
    bundle.removeBundle = function() {
      var removeRequest = reqwest({
        url: '/api/bundles/'+bundleId,
        method: 'delete',
        type: 'json'
      });
      removeRequest.then(function() {
        console.log("ok", arguments)
        existingModel.bundles.remove(this);
      }.bind(this), function() {
        console.log("error", arguments)
      })
    };
  }

  var existingModel = {
    bundles: ko.observableArray(),
    availableSections: availableSections
  };

  var request = reqwest({
    url: '/api/bundles',
    method: 'get',
    type: 'json'
  });
  request.then(function(response) {
    response.data.forEach(function(b) {
      var bundle = ko.mapping.fromJS(b);
      hookBundle(bundle);
      existingModel.bundles.push(bundle);
    });
  });

  var existingNode = document.getElementById('bundle-existing');
  ko.applyBindings(existingModel, existingNode);




  var creationModel = {
    createSlugInput: ko.observable(""),
    createTitleInput: ko.observable(""),
    createBackgroundInput: ko.observable(""),
    createSectionInput: ko.observableArray(),
    availableSections: availableSections,
    createBundle: function() {
      var slug = this.createSlugInput();
      var title = this.createTitleInput();
      var background = this.createBackgroundInput();
      var section = this.createSectionInput()[0];
      var request = reqwest({
        url: '/api/bundles',
        method: 'post',
        type: 'json',
        data: {id: slug, title: title, background_uri: background, section: section}
      });
      request.then(function(response) {
        console.log("success!", arguments);
        var bundle = ko.mapping.fromJS(response.data);
        hookBundle(bundle);
        existingModel.bundles.push(bundle);
        // reset input
        this.createSlugInput("");
        this.createTitleInput("");
      }.bind(this), function() {
        console.log("bundle creation failed!");
      });
    }
  };

  var creationNode = document.getElementById('bundle-add');
  ko.applyBindings(creationModel, creationNode);
}

window.addEventListener('load', everything);
