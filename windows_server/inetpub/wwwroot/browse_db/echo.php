<?php
header('Content-type: text/plain');
echo '<pre>'; 
print_r($_SERVER); 
echo '</pre>';
var_dump($_POST);



echo dirname($_SERVER['PHP_SELF']);

