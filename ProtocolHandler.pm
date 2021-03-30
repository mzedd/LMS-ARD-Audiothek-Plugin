package Plugins::ARDAudiothek::ProtocolHandler;

# Handler for ardaudiothek:// URLS

use strict;
#use base qw(Slim::Player::Protocols::HTTPS);

use Slim::Utils::Log;
use Plugins::ARDAudiothek::API;

my $log = logger('plugin.ardaudiothek');

sub overridePlayback {
    my ($class, $client, $url) = @_;

    my $id = $url;
    $id =~ s/ardaudiothek:\/\///;

    Plugins::ARDAudiothek::API->getItem(
        sub {
            my $content = shift;
            my @items;

            $log->info($content->{_links}->{"mt:bestQualityPlaybackUrl"}->{href});

            push @items, Slim::Schema->updateOrCreate({ url => $content->{_links}->{"mt:bestQualityPlaybackUrl"}->{href} });
            
            $client->execute([ 'playlist', 'clear' ]);
	        $client->execute([ 'playlist', 'addtracks', 'listRef', \@items ]);
	        $client->execute([ 'play' ]);
        },{
            id => $id
        }
    );

    return 1;
}

sub canDirectStream { 
    return 1;
}

sub contentType {
    return 'mp3';
}

sub isRemote { 1 }
#sub new {
#    my ($class, $args) = @_;
#
#    my $client = $args->{client};
#    my $song = $args->{song};
#    my $streamURL = $song->streamURL() || return;
#
#
#    $log->info("Moin");
#
#    $log->info($streamURL);
#}

#sub scanUrl {
#    my ($class, $url, $args) = @_;
#	
#    $log->info($url);
#
#    my $id = $url;
#    $id =~ s/ardaudiothek:\/\///;
#
#    $log->info(Data::Dump::dump($args->{song}->currentTrack()));
#
#    Plugins::ARDAudiothek::API->getItem(
#        sub {
#            my $content;
#
#            $args->{cb}->($content->{_links}->{"mt:bestQualityPlaybackUrl"}->{href});
#        },{
#            id => $id
#        }
#    );
#
#}

#sub scanUrl {
#    my ($class, $url, $args) = @_;
#	$args->{cb}->( $args->{song}->currentTrack() );
#}
#
#sub getNextTrack {
#    my ($class, $song, $successCb, $errorCb) = @_;
#    
#    my $url = $song->currentTrack()->url;
#    my $id = $url;
#    $id =~ s/ardaudiothek:\/\///;
#
#    Plugins::ARDAudiothek::API->getItem(
#        sub {
#            my $content;
#
#            $successCb->($content->{_links}->{"mt:bestQualityPlaybackUrl"}->{href});
#        },{
#            id => $id
#        }
#    );
#}
#
#sub gotNextTrack {
#    $log->info("Moin");
#}


1;
