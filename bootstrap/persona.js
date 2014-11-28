if(document.querySelector("#login")){
  document.querySelector("#login").addEventListener("click", function(e) {
    navigator.id.request();
    e.preventDefault()
  }, false);  
}


if(document.querySelector("#logout")){
  document.querySelector("#logout").addEventListener("click", function(e) {
    navigator.id.logout();
    e.preventDefault()
  }, false);  
}

navigator.id.watch({
  onlogin: function(assertion) {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", "/persona/verify", true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.addEventListener("loadend", function(e) {
      var data = JSON.parse(this.responseText);
      if (data && data.status === "okay") {
        console.log("You have been logged in as: " + data.email);
        if(!window.email) location.href = "/";
      }
    }, false);

    xhr.send(JSON.stringify({
      assertion: assertion
    }));

  },
  onlogout: function() {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", "/persona/logout", true);
    xhr.addEventListener("loadend", function(e) {
      if(window.email){
        location.href = "/";
      }else{
        document.querySelector("#login").style.display = ''
      }
    });
    xhr.send();
  }
});