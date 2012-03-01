// array of music ids to zip up
var musicToZip=new Array();

function checkIfEnterKey(e){
   if(e && e.keyCode == 13){
      musicSearch();
   }
}

function musicSearch(){
	var url="includes/musicSearch.php";

	// grab data
	var search = $('#searchField').val();
    var searchArtist = false;
    var searchAlbum = false;
    var searchTitle = false;

    // build AJAX request
    var data = "search="+search;

    if($('#artist').attr('checked')){
        searchArtist = true;
        data = data + "&searchArtist=true";
    }
    else {
        searchArtist = false;
        data = data + "&searchArtist=false";
    }
    if( $('#album').attr('checked')){
        searchAlbum = true;
        data = data + "&searchAlbum=true";
    }
    else{
        searchAlbum = false;
        data = data + "&searchAlbum=false";
    }

    if($('#title').attr('checked')){
        searchTitle = true;
        data = data + "&searchTitle=true";
    }
    else{
        searchTitle = false;
        data = data + "&searchTitle=false";
    }

    if(search !== ""){
        if(searchArtist === true || searchAlbum === true || searchTitle === true){
            showLoading("content");

            // perform AJAX call
            var resp = $.post(url, data)
                .error(function(err){showError("There was an error in contacting the server!", err.responseText);})
                .complete(function(data){showResults(data.responseText);})
            }
    }
}

function showResults(text){
    $('#content').html(text);
	$('#content').fadeIn('slow');
}

function showError(error){
    alert(error);
}

function showLoading(divID){
	$("#"+divID).html('<center><img src=\"images/ajax-loader.gif\"/></center>');
    $("#"+divID).fadeIn('slow');
}

function addFileToArray(id){
    if(!contains(musicToZip, id)){
        musicToZip.push(id);
    }
    if(musicToZip.length === 1){
        $('#downloadList').html("You have " +musicToZip.length + " file Ready to " + "<a href=\"#\" " +
            "onclick='Javascript: downloadFiles()'>Download</a> " );
        $('#downloadList').fadeIn('slow');
    }
    if(musicToZip.length >= 2){
            $('#downloadList').html("You have " +musicToZip.length + " files Ready to " + "<a href=\"#\" " +
                "onclick='Javascript: downloadFiles()'>Download</a> " );
            $('#downloadList').fadeIn('slow');
        }
}
function contains(array, string) {
    for (var i = 0; i < array.length; i++) {
        if (array[i] == string) {
            return true;
        }
    }
    return false;
}
function downloadFiles() {
    var url="includes/downloadFiles.php";

        // build AJAX request
        var data ="filesToGet=" + musicToZip[0];
        for (var i = 1; i < musicToZip.length; i++) {
            data = data + "," +  musicToZip[i];
        }

        showLoading("downloadList");
        musicToZip=new Array();

        // perform AJAX call
        var resp = $.post(url, data)
            .error(function(err){showError("There was an error in contacting the server!", err.responseText);})
            .complete(function(data){showDownloadResults(data.responseText);})
}

function showDownloadResults(text){
    $('#downloadList').html(text);
	$('#downloadList').fadeIn('slow');
}