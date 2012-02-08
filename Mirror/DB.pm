package Mirror::DB;

use strict;
use warnings;
use Storable qw();

use vars qw($DB_FILE);

sub set {
    $DB_FILE = shift;
}

sub store {
    my $db = shift;

    # Storable doesn't clone the tied hash as needed
    # so we have do it the ugly way:
    my $VAR1;
    {
	use Data::Dumper;
	$Data::Dumper::Purity = 1;
	$Data::Dumper::Indent = 0;

	my $clone = Dumper($db);
	eval $clone;
    }

    Storable::store ($VAR1, $DB_FILE.'.new')
	or die ("failed to store to $DB_FILE.new: $!");
    rename ($DB_FILE.'.new', $DB_FILE)
	or die("failed to rename $DB_FILE.new: $!");

}

1;
