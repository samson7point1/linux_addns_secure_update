<!DOCTYPE html>
<html>
<body>

<?php

// DB Connection Info
$db_driver	= "sqlsrv";
$db_address = "acmeautomation.database.windows.net";
$db_port	= "1433";
$db_proto	= "tcp";
$db_user	= "sqladmin";
$db_pass	= "secret";

// Display Settings
$rows_per_page = 50;

// Process Arguments
if ( isset($_GET['db']) ) {
	$db_name	= $_GET['db'];
}

if ( isset( $_GET['table']) ) {
	$db_table	= $_GET['table'];
}

if ( isset($_GET['page']) ) {
	$this_page	= $_GET['page'];
} else {
	$this_page = 0;
} 


if(!isset($db_table) || !$db_table)  {
	echo 'Mandatory parameter [table] is missing or empty';
	exit;
}


//write out header
echo "<span style=\"font-family:Arial;font-size:22px;font-style:normal;font-weight:bold;text-transform:none;color:000000;\">Database Name: </span>";
echo "<span style=\"font-family:Arial;font-size:22px;font-style:normal;font-weight:bold;text-decoration:underline;text-transform:none;color:000000;\">$db_name</span><br>\n";
echo "<br>";
echo "<span style=\"font-family:Arial;font-size:18px;font-style:normal;font-weight:bold;text-transform:none;color:000000;\">Table Name: </span>";
echo "<span style=\"font-family:Arial;font-size:18px;font-style:normal;font-weight:bold;text-decoration:underline;text-transform:none;color:000000;\">$db_table</span><br>\n";
echo "<br>";



class TableRows extends RecursiveIteratorIterator {
     function __construct($it) {
         parent::__construct($it, self::LEAVES_ONLY);
     }

     function current() {
         return "<td style='width: 150px; border: 1px solid black;'>" . parent::current(). "</td>";
     }

     function beginChildren() {
         echo "<tr>";
     }

     function endChildren() {
         echo "</tr>" . "\n";
     }
}


try {
    
	// create PDO
	$conn = $db = new PDO ( "$db_driver:server = $db_proto:$db_address,$db_port; Database = $db_name", "$db_user", "$db_pass", [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

	// get total row count for the table
	$stmt = $conn->prepare("SELECT COUNT(*) from $db_table");
	$stmt->execute();
	$result = $stmt->fetchAll(PDO::FETCH_COLUMN);
	$row_count = $result[0];
	
	// set query range
	$range_start = ( $this_page * $rows_per_page ) + 1;
	$range_end = $range_start + $rows_per_page;
	

	// format query statement
	$stmt = $conn->prepare("SELECT * FROM ( SELECT ROW_NUMBER() OVER ( ORDER BY id DESC ) AS RowNum, * FROM $db_table ) AS RowConstrainedResult WHERE RowNum >= $range_start AND RowNum < $range_end ORDER BY RowNum");

	// execute query
	$stmt->execute();

     // set the resulting array to associative
     $result = $stmt->setFetchMode(PDO::FETCH_ASSOC);

     // start open the column headings table
	echo "<table style='border: solid 1px black;'>";
	echo "<tr>";

	// print column headings
     for ($i = 0; $i < $stmt->columnCount(); $i++) {
    		$col = $stmt->getColumnMeta($i);
		if ( $col['name'] != "RowNum" ) {
          		echo "<th>";
			echo $col['name'];
			echo "</th>";
		}
		
	}
	// close table row
	echo "</tr>";
	


	// populate the rows
     foreach(new TableRows(new RecursiveArrayIterator($stmt->fetchAll())) as $k=>$v) {
		if ( $k != "RowNum" ) {
			echo $v;
		}
     }

	echo "</table>";

	// Create links to next and previous page as appropriate
	if ( $row_count > $rows_per_page ) {
		
		$next_page = $this_page + 1;		

		if ( ( $next_page * $rows_per_page ) <= $row_count ) { 
			echo "&nbsp <a href=\"https://$_SERVER[SERVER_NAME]/$_SERVER[PHP_SELF]?db=$db_name&table=$db_table&page=$next_page\">Previous $rows_per_page Records.</a>";
		}	
	}
	if ( $this_page > 0 ) {
		$prev_page = $this_page -1;
		echo "&nbsp <a href=\"https://$_SERVER[SERVER_NAME]/$_SERVER[PHP_SELF]?db=$db_name&table=$db_table&page=$prev_page\"> Next $rows_per_page Records.</a>";
		
	}

	echo "<br>";



}
catch(PDOException $e) {
     echo "Error: " . $e->getMessage();
}


$conn = null;
?> 

</body>
</html>
