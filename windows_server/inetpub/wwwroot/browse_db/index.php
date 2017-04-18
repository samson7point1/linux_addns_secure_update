<!DOCTYPE html>
<html>
<body>

<?php

$db_driver		= "sqlsrv";
$db_address = "acmeautomation.database.windows.net";
$db_port	= "1433";
$db_proto	= "tcp";
$db_user	= "sqladmin";
$db_pass	= "secret";
$db_name	= "ACMEAutomation";

$rel_path	= dirname($_SERVER['PHP_SELF']);

//write out header
echo "<span style=\"font-family:Arial;font-size:22px;font-style:normal;font-weight:bold;text-transform:none;color:000000;\">Database Name: </span>";
echo "<span style=\"font-family:Arial;font-size:22px;font-style:normal;font-weight:bold;text-decoration:underline;text-transform:none;color:000000;\">$db_name</span><br>\n";

echo "<br><br>";
echo "Click on a table to browse.";
try {
    
	// create PDO
	$conn = new PDO ( "$db_driver:server = $db_proto:$db_address,$db_port; Database = $db_name", "$db_user", "$db_pass", [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

	// format query statement
	$stmt = $conn->prepare("SELECT table_name FROM information_schema.tables");

	// execute query
	$stmt->execute();

     // set the resulting array to associative
	$result = $stmt->fetchAll(PDO::FETCH_COLUMN);
	
	// open table
	echo "<table border=\"1\" style=\"width:25%\">\n";
	// print table list
	foreach($result as $table_name){
		if ($table_name != "database_firewall_rules") {
			echo "<tr><td>"; 
			echo "&nbsp <a href=\"https://$_SERVER[SERVER_NAME]$rel_path/get_table.php?db=$db_name&table=$table_name\">$table_name<br>";
			echo "</td></tr>\n";
		}
	}

     
	// close table
	echo "</table>";
	

}
catch(PDOException $e) {
     echo "Error: " . $e->getMessage();
}
$conn = null;

?> 

</body>
</html>
