<?php
	require_once('config.php');
	
	
	$con = mysql_connect('localhost',$dbusername,$dbpassword);
	@mysql_select_db($database) or die( "Unable to select database");

	function dbQuery($query){
		global $con;
		//global $dbusername, $dbpassword, $database;
		if ( defined('MYSQL_DEBUG') ){
			echo "$query<br />\n";
		}
		$result = mysql_query($query, $con);
		return $result;
	}

/* creates a compressed zip file */
/* Function Curtsy of the Internet*/
function create_zip($files = array(),$destination = '',$overwrite = false) {
	//if the zip file already exists and overwrite is false, return false
	if(file_exists($destination) && !$overwrite) { return false; }
	//vars
	$valid_files = array();
	//if files were passed in...
	if(is_array($files)) {
		//cycle through each file
		foreach($files as $file) {
			//make sure the file exists
			if(file_exists($file)) {
				$valid_files[] = $file;
			}
		}
	}
	//if we have good files...
	if(count($valid_files)) {
		//create the archive
		$zip = new ZipArchive();
		if($zip->open($destination,$overwrite ? ZIPARCHIVE::OVERWRITE : ZIPARCHIVE::CREATE) !== true) {
			return false;
		}
		//add the files
		foreach($valid_files as $file) {
			$zip->addFile($file,$file);
		}
		//debug
		//echo 'The zip archive contains ',$zip->numFiles,' files with a status of ',$zip->status;

		//close the zip -- done!
		$zip->close();

		//check to make sure the file exists
		return file_exists($destination);
	}
	else
	{
		return false;
	}
}
?>