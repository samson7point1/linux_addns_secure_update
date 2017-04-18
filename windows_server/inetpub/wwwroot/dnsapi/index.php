<?php
// Enforce HTTPS for all traffic
if( !isset($_SERVER['HTTPS']) || $_SERVER['HTTPS'] != 'on')	{
	header("HTTP/1.1 301 Moved Permanently");
	header('Location: https://' . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI']);
	exit();
}

// All output from this point forward must be JSON
header('Content-Type: application/json');

// Response array we will convert to JSON
$RESPONSE = array(
				"success"	=> false,
				"error"		=> "Requests to this API must be versioned",
			);

print json_encode($RESPONSE);
