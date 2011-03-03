# lib/Core/IRC.pm - Core IRC hooks and timers.
# Copyright (C) 2010-2011 Xelhua Development Group, et al.
# This program is free software; rights to this code are stated in doc/LICENSE.
package Core::IRC;
use strict;
use warnings;
use English qw(-no_match_vars);
use API::Std qw(hook_add timer_add conf_get);
use API::IRC qw(notice usrc);

our (%usercmd);

# CTCP VERSION reply.
hook_add("on_uprivmsg", "ctcp_version_reply", sub {
    my (($src, @msg)) = @_;

    if ($msg[0] eq "\001VERSION\001") {
        if (Auto::RSTAGE ne 'd') {
            notice($src->{svr}, $src->{nick}, "\001VERSION ".Auto::NAME." ".Auto::VER.".".Auto::SVER.".".Auto::REV.Auto::RSTAGE." ".$OSNAME."\001");
        }
        else {
            notice($src->{svr}, $src->{nick}, "\001VERSION ".Auto::NAME." ".Auto::VER.".".Auto::SVER.".".Auto::REV.Auto::RSTAGE."-$Auto::VERGITREV ".$OSNAME."\001");
        }
    }

    return 1;
});

# QUIT hook; delete user from chanusers.
hook_add("on_quit", "quit_update_chanusers", sub {
    my (($src, undef)) = @_;
    my %src = %{ $src };

    # Delete the user from all channels.
    foreach my $ccu (keys %{ $Proto::IRC::chanusers{$src{svr}}}) {
        if (defined $Proto::IRC::chanusers{$src{svr}}{$ccu}{$src{nick}}) { delete $Proto::IRC::chanusers{$src{svr}}{$ccu}{$src{nick}}; }
    }

    return 1;
});

# Modes on connect.
hook_add("on_connect", "on_connect_modes", sub {
    my ($svr) = @_;

    if (conf_get("server:$svr:modes")) {
    	my $connmodes = (conf_get("server:$svr:modes"))[0][0];
    	API::IRC::umode($svr, $connmodes);
    }

    return 1;
});

# Self-WHO on connect.
hook_add('on_connect', 'on_connect_selfwho', sub {
    my ($svr) = @_;

    API::IRC::who($svr, $Proto::IRC::botinfo{$svr}{nick});

    return 1;
});

# Plaintext auth.
hook_add("on_connect", "plaintext_auth", sub {
    my ($svr) = @_;
    
    if (conf_get("server:$svr:idstr")) {
    	my $idstr = (conf_get("server:$svr:idstr"))[0][0];
    	Auto::socksnd($svr, $idstr);
    }

    return 1;
});

# Auto join.
hook_add("on_connect", "autojoin", sub {
    my ($svr) = @_;

    # Get the auto-join from the config.
    my @cajoin = @{ (conf_get("server:$svr:ajoin"))[0] };
    
    # Join the channels.
    if (!defined $cajoin[1]) {
    	# For single-line ajoins.
    	my @sajoin = split(',', $cajoin[0]);
    	
        foreach (@sajoin) {
            # Check if a key was specified.
            if ($_ =~ m/\s/xsm) {
                # There was, join with it.
                my ($chan, $key) = split / /;
                API::IRC::cjoin($svr, $chan, $key);
            }
            else {
                # Else join without one.
    	        API::IRC::cjoin($svr, $_);
            }
        }
    }
    else {
    	# For multi-line ajoins.
    	foreach (@cajoin) {
            # Check if a key was specified.
            if ($_ =~ m/\s/xsm) {
                # There was, join with it.
                my ($chan, $key) = split / /;
                API::IRC::cjoin($svr, $chan, $key);
            }
            else {
                # Else join without one.
                API::IRC::cjoin($svr, $_);
            }
        }
    }
    # And logchan, if applicable.
    if (conf_get('logchan')) {
        my ($lcn, $lcc) = split '/', (conf_get('logchan'))[0][0];
        if ($lcn eq $svr) {
            API::IRC::cjoin($svr, $lcc);
        }
    }

    return 1;
});

# WHO reply.
hook_add('on_whoreply', 'selfwho.getdata', sub {
    my (($svr, $nick, undef, $user, $mask, undef, undef, undef, undef)) = @_;

    # Check if it's for us.
    if ($nick eq $Proto::IRC::botinfo{$svr}{nick}) {
        # It is. Set data.
        $Proto::IRC::botinfo{$svr}{user} = $user;
        $Proto::IRC::botinfo{$svr}{mask} = $mask;
    }

    return 1;
});

# ISUPPORT - Set prefixes and channel modes.
hook_add('on_isupport', 'core.prefixchanmode.getdata', sub {
    my (($svr, @ex)) = @_;

    # Find PREFIX and CHANMODES.
    foreach my $ex (@ex) {
    	if ($ex =~ m/^PREFIX/xsm) {
    		# Found PREFIX.
    		my $rpx = substr($ex, 8);
    		my ($pm, $pp) = split('\)', $rpx);
    		my @apm = split(//, $pm);
    		my @app = split(//, $pp);
    		foreach my $ppm (@apm) {
    			# Store data.
    			$Proto::IRC::csprefix{$svr}{$ppm} = shift(@app);
    		}
    	}
        elsif ($ex =~ m/^CHANMODES/xsm) {
            # Found CHANMODES.
            my ($mtl, $mtp, $mtpp, $mts) = split m/[,]/xsm, substr($ex, 10);
            # List modes.
            foreach (split(//, $mtl)) { $Proto::IRC::chanmodes{$svr}{$_} = 1; }
            # Modes with parameter.
            foreach (split(//, $mtp)) { $Proto::IRC::chanmodes{$svr}{$_} = 2; }
            # Modes with parameter when +.
            foreach (split(//, $mtpp)) { $Proto::IRC::chanmodes{$svr}{$_} = 3; }
            # Modes without parameter.
            foreach (split(//, $mts)) { $Proto::IRC::chanmodes{$svr}{$_} = 4; }
        }
    }

    return 1;
});

sub clear_usercmd_timer 
{
    # If ratelimit is set to 1 in config, add this timer.
    if ((conf_get('ratelimit'))[0][0] eq 1) {
        # Clear usercmd hash every X seconds.
        timer_add('clear_usercmd', 2, (conf_get('ratelimit_time'))[0][0], sub {
            foreach (keys %Core::IRC::usercmd) {
                $Core::IRC::usercmd{$_} = 0;
            }

            return 1;
        });
    }

    return 1;
}

# Server data deletion on disconnect.
hook_add('on_disconnect', 'core.irc.deldata', sub {
    my ($svr) = @_;

    # Delete all data related to the server.
    if (defined $Proto::IRC::got_001{$svr}) { delete $Proto::IRC::got_001{$svr} }
    if (defined $Proto::IRC::botinfo{$svr}) { delete $Proto::IRC::botinfo{$svr} }
    if (defined $Proto::IRC::botchans{$svr}) { delete $Proto::IRC::botchans{$svr} }
    if (defined $Proto::IRC::chanusers{$svr}) { delete $Proto::IRC::chanusers{$svr} }
    if (defined $Proto::IRC::csprefix{$svr}) { delete $Proto::IRC::csprefix{$svr} }
    if (defined $Proto::IRC::chanmodes{$svr}) { delete $Proto::IRC::chanmodes{$svr} }
    if (defined $Proto::IRC::cap{$svr}) { delete $Proto::IRC::cap{$svr} }

    return 1;
});


1;
# vim: set ai et sw=4 ts=4:
