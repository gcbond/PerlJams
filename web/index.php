<html>
	<head>
		<title>Music database search</title>
		<link href="css/css.css" rel="stylesheet" type="text/css">
		<script type="text/javascript" src="scripts/jquery.js"></script>
		<script type="text/javascript" src="scripts/music.js"></script>
	</head>
	<body>
        <div id= "searchContainer">
            <table id="searchContainerTable">
                <tr>
                    <td>
                        <div id= "header">
                            Please use the search field to search my music collection...
                        </div>
                    </td>
                    <td>
                        <div id="downloadList">

                        </div>
                    </td>
                    <td>
                        <div id="search">
                            Search: <input type="text" id="searchField" name="search" onKeyPress="Javascript: checkIfEnterKey(event);"/>
                            <input type="checkbox" id="artist" name="artist" value="atrist" checked/>Artist
                            <input type="checkbox" id="album" name="album" value="album" checked/>Album
                            <input type="checkbox" id="title" name="title" value="title" checked/>Title
                            <input type="button" name="Search" value="Search" onClick="javascript: musicSearch();"/>
                        </div>
                    </td>
                </tr>
            </table>
        </div>
        <div id="content">
        </div>
	</body>
</html>