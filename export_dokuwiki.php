#!/usr/bin/php
<?php
define('DOKU_INC', dirname(__FILE__).'/dokuwiki/');
require_once(DOKU_INC.'inc/init.php');
require_once(DOKU_INC.'inc/common.php');
require_once(DOKU_INC.'inc/events.php');
require_once(DOKU_INC.'inc/parserutils.php');
require_once(DOKU_INC.'inc/auth.php');

function ensure_utf8($content) {
      return mb_convert_encoding($content, 'UTF-8',
          mb_detect_encoding($content, 'UTF-8, ISO-8859-1', true));
}

function p_file_xhtml($id, $excuse=false){
    if(@file_exists($id)) return p_cached_output($id,'xhtml',$id);
    return p_wiki_xhtml($id, '', $excuse);
}

function process_wikifile($collection, $wiki_file, $wiki_namespaces, $wiki_name){
  $wiki_id = sprintf("%s:%s", implode($wiki_namespaces, ":"), $wiki_name);
  echo "$wiki_id\n";
  $wiki_html = ensure_utf8(p_file_xhtml($wiki_file, false));
  $wiki_text = ensure_utf8(file_get_contents($wiki_file));
  $collection->insert(array(wiki_name => $wiki_name, wiki_id => $wiki_id, wiki_namespaces => $wiki_namespaces, wiki_text => $wiki_text, wiki_html => $wiki_html));
}

function process_wikifiles($collection, $basedir, $namespaces){
  $directory = "$basedir/" . join('/', $namespaces);
  if ($handle = opendir($directory)) {
      while (false !== ($entry = readdir($handle))) {
          $file = "$directory/$entry";
          if ($entry == "." || $entry == "..") {
            continue;
          }
          if(is_dir($file)){
            process_wikifiles($collection, $basedir, array_merge($namespaces, array($entry)));
            continue;
          }
          $name = preg_replace('/\.txt$/', '', $entry);
          process_wikifile($collection, $file, $namespaces, $name);
      }
      closedir($handle);
  }
}

$pagedir= "$argv[1]/pages";

$m = new MongoClient( "mongodb://localhost:27016");
$db = $m->dokuwiki2evernote;
$collection = $db->selectCollection('pages');


process_wikifiles($collection, "$pagedir", array());

// if($argc > 1) {
//   array_shift($argv);
//   foreach($argv as $file) {
//     echo $file . "\n";
//   }
// } else {
//   if(!isset($argv[0])) $argv[0] = __FILE__;
//   echo "<h1>This is NOT web application, this is PHP-CLI application (for commandline)</h1><pre>\n";
//   echo "Note that you will probably need to install php-cgi package. Check if you have 'php' command on your system\n";
//   echo "php-cgi binary is commonly placed in /usr/bin/php\n\n";
//   echo "Usage examples:\n";
//   echo "\tphp ".$argv[0]." start\n\t\t- export single page 'start'\n";
//   echo "\tphp ".$argv[0]." start > start.html\n\t\t- export single page 'start' to file start.html\n";
//   echo "\tphp ".$argv[0]." start wiki:syntax\n\t\t- export multiple pages\n";
//   echo "\tphp ".$argv[0]." data/pages/start.txt\n\t\t- export single page using filename\n";
//   echo "\tphp ".$argv[0]." data/pages/wiki/*\n\t\t- export whole namespace 'wiki'\n";
//   echo "\tphp ".$argv[0]." $(find ./data/pages/wiki/)\n\t\t- export whole namespace 'wiki' and it's sub-namespaces\n";
//   echo "\tphp ".$argv[0]." $(find ./data/pages/) > dump.html\n\t\t- dump whole wiki to file dump.html\n";
//   echo "\nOnce you have HTML dump you need, you can add optional CSS styles or charset-encoding header to it,\n";
//   echo "then you are ready to distribute it, or (eg.) convert it to PDF using htmldoc, OpenOffice.org or html2pdf webservice.\n\n";
// }
