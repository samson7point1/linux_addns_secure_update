<?php

// Require HTTPS
if( !isset($_SERVER['HTTPS']) || $_SERVER['HTTPS'] != 'on')	{
   header("HTTP/1.1 301 Moved Permanently");
   header('Location: https://' . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI']);
   exit();
}

// Function to prepend values to an associatiave array
function array_unshift_assoc(&$arr, $key, $val)
{
    $arr = array_reverse($arr, true);
    $arr[$key] = $val;
    return array_reverse($arr, true);
} 

// All output from this point forward will be JSON
header('Content-Type: application/json');	

// Response array that will be converted to JSON
$RESPONSE = array();


// Handle non-post requests as an error
if ($_SERVER['REQUEST_METHOD'] != 'POST') {
   $RESPONSE['success']= false;
   $RESPONSE['error']	= 'Request method not supported';
   exit(json_encode($RESPONSE));
}

// Handle missing actions as an error
if ( !isset($_POST['action']) || !$_POST['action'] ) {
   $RESPONSE['success']= false;
   $RESPONSE['error']	= 'Request action invalid';
   exit(json_encode($RESPONSE));
}

// copy _POST into an editable variable
$REQUEST = $_POST;

// set ACTION to the POST action - this will translate later on to the literal file name of a powershell script
$ACTION = $_POST['action'];

// remove "action" from the REQUEST as we've already processed that key
unset($REQUEST['action']);

// prepend the sourceIP element to the array - this will be used to validate DNS update requests against the requesting IP
array_unshift_assoc($REQUEST,'sourceIP',"$_SERVER[REMOTE_ADDR]"); 


// set debug level
$DEBUG = 0;

// Set debug values
if (isset($REQUEST['debug']) && $REQUEST['debug']) {
   $DEBUG = $REQUEST['debug'];	
   $RESPONSE['debug'] = $DEBUG;
   $RESPONSE['action'] = $ACTION;
   $RESPONSE['request'] = $REQUEST;
}

// Create a PS1 (powershell script) filename from the action passed in POST
$TRY = $ACTION . '.ps1';

// If the file doesn't exist die
if(!file_exists($TRY)) {
   $RESPONSE['success']= false;
   $RESPONSE['error']	= 'Request action not found';
   exit(json_encode($RESPONSE));
}

//read the PS1 file
$PS1 = file_get_contents($TRY);

//create a REGEX to parse the parameters block of the PS1 file
$REGEX = "/param\((.+)\)/misU";

//need to make sure that we can find the parameters block
if(!preg_match($REGEX,$PS1,$HITS)) {			
   $RESPONSE['success']= false;		
   $RESPONSE['error']	= 'Could not identify requested action parameters';
   exit(json_encode($RESPONSE));
}

//set the PHP parameters to match the first element of the array returned by the regex
$PARAMS = $HITS[1];

//set a new regex to parse mandatory parameters from the block
$REGEX = "/\s+\[parameter\(\s+mandatory=.+?\)\]\s+\[(\S+)\]\s+\$(\w+)/msiU";

//make sure that for each mandatory parameter we have an identical parameter received in the POST
if(preg_match($REGEX,$PARAMS,$HITS)) {	
   foreach($HITS as $HIT) {
      // [2] is param name, [1] is the data type (unused currently)
      $PARAM = $HIT[2];	

      // if there is no matching parameter set, then error out
      if(!isset($REQUEST[$PARAM]) || !$REQUEST[$PARAM]) {
         $RESPONSE['success']= false;
         $RESPONSE['error']	= 'Mandatory parameter ' . $PARAM . ' is missing or empty';
         exit(json_encode($RESPONSE));
      }
   }
}

// build the powershell command string
$COMMAND = 'powershell.exe -noninteractive -file';

// appended chunks to the commandline must begin with space
$COMMAND .= ' ./' . $TRY;

// add all parameters in the order provided
foreach($REQUEST as $KEY => $VALUE) {	
   // if its an array, we need to combine the elements into @(1,2,3) format
   if(is_array($VALUE)) {
      $COMMAND .= ' -' . $KEY . ' @(' . implode(',',$VALUE) . ')';

   // otherwise simple command strings get appended
   }else{
      $COMMAND .= ' -' . $KEY . ' ' . $VALUE;
   }
}

// if debugging send the whole command back in the response
if ($DEBUG) {	
   $RESPONSE['command'] = $COMMAND;
}

// execute the powershell string and capture the response
$OUTPUT = shell_exec($COMMAND);	

// decode the PS1 output as JSON
$RESPONSE['response'] = json_decode($OUTPUT, true);

// copy success response
if (isset($RESPONSE['response']['success'])) {
   $RESPONSE['success'] = $RESPONSE['response']['success'];
}

// copy failure response
if (isset($RESPONSE['response']['error'])) {
   $RESPONSE['error'] = $RESPONSE['response']['error'];
}

// If, for some reason, the request couldn't be captured as JSON, then just return the raw response
if(json_last_error() !== JSON_ERROR_NONE) {
   $RESPONSE['response'] = trim($OUTPUT);
}

// terminate and respond with JSON
exit(json_encode($RESPONSE));
