# Module: FML. See below for documentation.
# Copyright (C) 2010-2011 Xelhua Development Group, et al.
# This program is free software; rights to this code are stated in doc/LICENSE.
package M::FML;
use strict;
use warnings;
use API::Std qw(cmd_add cmd_del trans);
use API::IRC qw(privmsg notice);
use Furl;
use HTML::Tree;

# Initialization subroutine.
sub _init {
    # Create the FML command.
    cmd_add('FML', 0, 0, \%M::FML::HELP_FML, \&M::FML::cmd_fml) or return;

    # Success.
    return 1;
}

# Void subroutine.
sub _void {
    # Delete the FML command.
    cmd_del('FML') or return;

    # Success.
    return 1;
}

# Help hash.
our %HELP_FML = (
    en => "This command will return a random FML quote. \2Syntax:\2 FML",
    de => "Dieser Befehl liefert eine zufaellige Zitat von FML. \2Syntax:\2 FML",
);

# Callback for FML command.
sub cmd_fml {
    my ($src, undef) = @_;

    # Create an instance of Furl.
    my $ua = Furl->new(
        agent => 'Auto IRC Bot',
        timeout => 5,
    );

    # Get the random FML via HTTP.
    my $rp = $ua->get('http://www.fmylife.com/random');

    if ($rp->is_success) {
        # If successful, get the content.
        my $tree = HTML::Tree->new();
        $tree->parse($rp->content);
        my $data = $tree->look_down('_tag', 'div', 'id', qr/^[0-9]/);

        # Parse it.
        my $fml = $data->as_text;
        $fml =~ s/\sFML.*//xsm;

        # Return the FML.
        privmsg($src->{svr}, $src->{chan}, "\2Random FML:\2 $fml FML");
        $tree->delete;
    }
    else {
        # Otherwise, send an error message.
        privmsg($src->{svr}, $src->{chan}, 'An error occurred while retrieving the FML.');
    }

    return 1;
}

# Start initialization.
API::Std::mod_init('FML', 'Xelhua', '1.02', '3.0.0a11');
# build: cpan=Furl,HTML::Tree perl=5.010000

__END__

=head1 NAME

 FML - A module for retrieving random FML quotes

=head1 VERSION

 1.02

=head1 SYNOPSIS

 <starcoder> !fml
 <blue> Random FML: Today, I told my mom I loved her a lot. Her reply? "Thanks." FML

=head1 DESCRIPTION

This module creates the FML command, which will retrieve a random FML quote
and message it to the channel.

=head1 DEPENDENCIES

This module depends on the following CPAN modules:

=over

=item L<Furl>

This is the HTTP agent used by this module.

=item L<HTML::Tree>

This is the HTML parser.

=back

=head1 AUTHOR

This module was written by Elijah Perrault.

This module is maintained by Xelhua Development Group.

=head1 LICENSE AND COPYRIGHT

This module is Copyright 2010-2011 Xelhua Development Group.

Released under the same licensing terms as Auto itself.

=cut

# vim: set ai et sw=4 ts=4:
