<?php
    require_once('functions.php');
    $file_paths = array();

    $filesToGet = $_POST["filesToGet"];
    $files = explode(",", $filesToGet);

    if(count($files) <= 200){
        foreach($files as $file){

            if(preg_match("/[0-9]/", $file)){
                $query = "Select `path` from `$tableName` WHERE id = '$file' LIMIT 1 ";
                $result = dbQuery($query);

                if(mysql_num_rows($result) > 0){
                    if($row = mysql_fetch_array($result)){
                             array_push($file_paths, "../" . $musicDirectory . $row['path']);
                    }
                }
            }
        }
        $rand = rand();
        $zip_file = create_zip($file_paths,'/var/www/htdocs/music/temp/music' . $rand . '.zip',true);
    }
    if($zip_file){
        $file = "temp/music" . $rand . ".zip";
        echo "<div id=\"zipFileDownload\"><a href=\"" . $file . "\">Download</a></div>";
    }

    else{
        echo "An error occurred while creating the zip-file, sorry.";
    }
?>