use strict;
use warnings;
use inc::Module::Install;

name 'Nginx-Simple';
all_from 'lib/Nginx/Simple.pm';
license 'perl';

WriteAll();
