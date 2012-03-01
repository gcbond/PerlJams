<?php
	require_once('functions.php');
    $search = $_POST["search"];
	
	$search = mysql_real_escape_string($search);
	
    $searchArtist = $_POST["searchArtist"];
    $searchAlbum = $_POST["searchAlbum"];
    $searchTitle = $_POST["searchTitle"];

	mysql_real_escape_string($search);

    if($search == ""){exit;}
    if($searchArtist == false && $searchAlbum == false && $searchTitle == false){exit;}

    $firstSet = false;
    $query = "SELECT * FROM `" . $tableName . "` WHERE ";
    if($searchArtist == "true"){
            if($firstSet){
                $query = $query . " OR `artist` LIKE '% $search%' OR `artist` LIKE '$search%' ";
            }
            else{
                $firstSet = true;
                $query = $query . " `artist` LIKE '% $search%' OR `artist` LIKE '$search%' ";
            }
    }
    if($searchAlbum == "true"){
            if($firstSet){
                $query = $query . " OR `album` LIKE '% $search%' OR `album` LIKE '$search%' ";
            }
            else{
                $firstSet = true;
                $query = $query . " `album` LIKE '% $search%' OR `album` LIKE '$search%' ";
            }
    }
    if($searchTitle == "true"){
            if($firstSet){
                $query = $query . " OR `title` LIKE '% $search%' OR `title` LIKE '$search%' ";
            }
            else{
                $firstSet = true;
                $query = $query . " `title` LIKE '% $search%' OR `title` LIKE '$search%' ";
            }
    }
    $query = $query . "ORDER BY `bitrate` DESC LIMIT 60";
	$result = dbQuery($query);
	
	if(mysql_num_rows($result) > 0){
        echo "<table id=\"musicList\">";
            echo "<tr id=\"musicListHeader\">
                    <td>Title<td>
                    <td>Artist<td>
                    <td>Album<td>
                    <td>Track Number<td>
                    <td>Bitrate<td>
                    <td>File Format<td>
                    <td>Download<td>
                    <td>Download-queue<td>
                 </tr>";
        $evenRow = true;
        while ($row = mysql_fetch_array($result)){
            $artist = $row['artist'];
            $album = $row['album'];
            $title = $row['title'];
            $track_number = $row['track_number'];
            $bitrate = $row['bitrate'];
            $file_extension = $row['file_extension'];
            $path = $row['path'];
            $id = $row['id'];

            if($evenRow){
                echo "<tr class=\"evenRow\">";
            }
            else {
                echo "<tr class=\"oddRow\">";
            }
            ?>
                    <td><?php echo $title;?><td>
                    <td><?php echo $artist;?><td>
                    <td><?php echo $album;?><td>
                    <td><?php echo $track_number;?><td>
                    <td><?php echo $bitrate;?><td>
                    <td><?php echo $file_extension;?><td>
                    <td><a target="_blank" href="<?php echo $musicDirectory . $path;?>">Download</a><td>
                   <td><a href="#" onClick="Javascript: addFileToArray(<?php echo $id; ?>);">Add to zip file</a><td>
                </tr>
            <?php
            $evenRow = !$evenRow;
        }
        echo "</table>";
	}
    else{
        echo "<center>Sorry, nothing matched your search</center>";
    }
?>