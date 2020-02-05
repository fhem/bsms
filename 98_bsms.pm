package main;
use strict;
use warnings;
#use JSON::API;
#use JSON;
use HTTP::Request ();
use JSON;
use Data::Dumper;
use JSON::XS;
use LWP::UserAgent;
use DateTime::Format::Strptime qw(strptime);
#use Time::ParseDate;
use DateTime;

my $ua = LWP::UserAgent->new;
$ua->agent("MyApp/0.1");



####GLOBAL###
{
	
	our $alarms;
	our $testalarm = 0;
	our $hash;
	
}

sub bsms_setreading($);

my %bsms_sets =
(
  "Testalarm"	=> "textField",
  "sessionid"					=> "textField",
 
);
		
#my %bsms_gets = (
#	"devices"	=> "",
#	"state"	=> "active:inactiv"
	
#);



sub bsms_Initialize($) {
    my ($hash) = @_;


    $hash->{DefFn}      = 'bsms_Define';
    $hash->{UndefFn}    = 'bsms_Undef';
    $hash->{SetFn}      = 'bsms_Set';
  	$hash->{NotifyFn}   = "bsms_Notify";
  	#$hash->{DeleteFn}   = "bsms_Delete";
   # $hash->{GetFn}      = 'bsms_Get';
    $hash->{AttrFn}     = 'bsms_Attr';
    $hash->{ReadFn}     = 'bsms_Read';
   # $hash->{Interval}   =  36;

    $hash->{AttrList} =
    	"msisdn/Tel ".
    	"Intervall ".
    	"Alarmdauer "
    	. $readingFnAttributes;
     #     #"formal:yes,no ",
     #     "devices:1,2,3,4 ".
     #     "formel ""Intervall"){
		#			our $hash->{intervall} = $attr_value;
			#		return undef;
		#		}
			#	elsif($attr_name eq "Alarmdauer"){
       #   . $readingFnAttributes;
        
        
}


sub bsms_Define($$) {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);

	
    if(int(@param) < 4) {
        return "too few parameters: define <name> bsms <customerID> <username> <password>";
    }
    
    $hash->{name}  = $param[0];
    $hash->{customer_id} = $param[2];
    $hash->{username} = $param[3];
    $hash->{password} = $param[4];
   # $hash->{poll} = $param[5];
    $hash->{STATE} = "active";

    return main($hash);
}



sub get_session($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 3, "X ($name) - get session";

my $url = "https://api.blaulichtsms.net/blaulicht/api/alarm/v1/dashboard/login";
my $header= [ 'Content-Type' => 'application/json'];

my $content = {   
	
		"customerId" => $hash->{customer_id},
    "username" => $hash->{username},
    "password" => $hash->{password},
    
  };
  
my $jcontent = JSON->new->utf8->encode($content);

my $req = HTTP::Request->new('POST', $url, $header , $jcontent);

# Pass request to the user agent and get a response back
my $res = $ua->request($req);
###

	if ($res->is_success) {

			my $message = $res->decoded_content;
			my $fromjson = from_json($message);
			my $obj = $fromjson->{"sessionId"};
			setreading($hash, "sessionID", $obj);
			$hash->{session_id} = $obj;
			return 1;
	}else {
		setreading($hash, "session", $res->status_line);
		set_state($hash, "Error Login");
		return undef;
	}

 	return undef ;
}

sub convert_time($){
	my ($obj) = @_;
	my $name = "BSMS";
	Log3 $name, 3, "X ($name) - convert Time";

	 my $timepattern = '%Y-%m-%dT%H:%M:%S.%NZ';
   my $Strp = DateTime::Format::Strptime->new(
    pattern   => $timepattern,
    locale    => 'de_DE',
    time_zone => 'UTC',
	);

	my $alarmtime = $Strp->parse_datetime($obj);
	my $tsalarm = $alarmtime->epoch;

	
	return $tsalarm;
	
}

sub get_alarms($){
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 3, "X ($name) - get alarms";
	my $session = $hash->{session_id};
	
	unless ($session) { get_session($hash);}
	
	
	
		my $url = "https://api.blaulichtsms.net/blaulicht/api/alarm/v1/dashboard/$session";


		my $req = HTTP::Request->new('GET', $url);

		# Pass request to the user agent and get a response back
		my $res = $ua->request($req);

		# Check the outcome of the response
		if ($res->is_success) {
			setreading($hash, "Info", $res->content);
			
				
			

			my $message = $res->decoded_content;

			my $fromjson = from_json($message);
	
		#	my $obj = $fromjson->{"alarms"}[0]{"alarmDate"};
	
			our $alarms =$fromjson;
	
			
  
		} else {
			set_state($hash, "error session");
			get_session($hash);
			setreading($hash, "Info", $res->status_line);
			
		}

		return  1;
		
	
}

sub is_alarm($){
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 3, "X ($name) - is Alarms";
	my $duration = 3600;
	
	if($hash->{alarmdauer} > 0 ) {
     $duration = $hash->{alarmdauer};
	}
	my $alarms = get_alarms($hash);
	my $dt = DateTime->now;
	my $tslocal = $dt->epoch;
	my $obj = our $alarms->{"alarms"}[0]{"alarmDate"};
	my $txt = our $alarms->{"alarms"}[0]{"alarmText"};
	my $time_lastalarm = convert_time($obj) ;
	my $timelastoffset = $time_lastalarm + $duration;
	
	my $dtt = DateTime->from_epoch( epoch => $time_lastalarm );
	$dtt->set_time_zone( "Europe/Berlin" );
	my $ymd    = $dtt->ymd('.'); # 1974.11.30 - also 'date'
	my $y   = $dtt->year;
	my $m  = $dtt->month; # 1-12 - you can also use '$dt->mon'
	my $d    = $dtt->day; # 1-31 - also 'day_of_month', 'mday'
	my $hms    = $dtt->hms; # 13:30:00
	my $timestr = "$d.$m.$y $hms";
	
	unless ($alarms) { return undef;}
	
	
	setreading($hash, "letzte_Alarm", $timestr);
	#setreading($hash, "duration", $timelastoffset);
	setreading($hash, "Meldetext", $txt);
	
	
	if($timelastoffset >= $tslocal or our $testalarm == 1){
		setreading($hash, "Alarm", "Alarm");
		set_state($hash, "Alarm");
		return 1;
			
	}else{
		setreading($hash, "Alarm", "kein Alarm");
		set_state($hash, "running");
		return undef;
	}
	
}


sub set_state($$) {
	my ($hash, $value) = @_;
	$hash->{STATE} = $value;
	return 1;
}

sub set_error($$) {
	my ($hash, $value) = @_;
	
}


sub main($) {
	my ($hash) = @_;
	my $intervall = 30;
	if( $hash->{intervall} > 0 ) {
     $intervall = $hash->{intervall};
	}
	my $timer = gettimeofday() + $intervall;
	my $start ="main";
	
	get_alarms($hash);
	is_alarm($hash);
	our $hash = $hash;
	
	RemoveInternalTimer($hash);
  InternalTimer($timer, $start, $hash,0);
}

sub setreading($$$) {
	my ($hash, $reading, $value) = @_;
	readingsBeginUpdate($hash);
	readingsBulkUpdate( $hash, $reading, $value );
	readingsEndUpdate( $hash, 1 );
}

sub getreading($$$) {	 
	my ($device, $reading, $hash) = @_;
	my $result = ReadingsVal($device, $reading, "");

	return $result
}



sub bsms_Undef($$) {
    my ($hash, $arg) = @_; 
    # nothing to do
    return undef;
}

#sub bsms_Get($@) {
#	my ($hash, @param) = @_;
#	return '"get bsms" needs at least one argument' if (int(@param) < 2);
#	
#	my $name = shift @param;
#	my $opt = shift @param;
#	if(!$bsms_sets{$opt}) {
#		my @cList = keys %bsms_sets;
#		return "Unknown argument $opt, choose one of " . join(" ", @cList);
#	}

#	return $bsms_sets{$opt};
#}

sub bsms_Notify($$)
{
  my ($own_hash, $dev_hash) = @_;
  my $ownName = $own_hash->{NAME}; # own name / hash

  return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled

  my $devName = $dev_hash->{NAME}; # Device that created the events

  my $events = deviceEvents($dev_hash,1);
  return if( !$events );

  foreach my $event (@{$events}) {
    $event = "Alarm: Alarm" if(!defined($event));

    # Examples:
    # $event = "readingname: value" 
    # or
    # $event = "INITIALIZED" (for $devName equal "global")
    #
    # processing $event with further code
  }
}

#sub bsms_Delete($$)    
#{                     
#	my ( $hash, $name ) = @_;       
##	# Löschen von Geräte-assoziiertem Temp-File
#unlink($attr{global}{modpath}."/FHEM/FhemUtils/$name.tmp";);
#
#	return undef;
#}

sub bsms_Set($@) {
	my ($hash, @param) = @_;
	
	return '"set bsms" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	my $value = join("", @param);
	
	if(!defined($bsms_sets{$opt})) {
		my @cList = keys %bsms_sets;
		return "opt$opt ,, val$value Unknown argument $opt, choose one of " . join(" ", @cList);
	}
			
	if($opt eq "Testalarm") 
	{	  
	 	 if($value eq "on") 
		{
		  our $testalarm = 1;
		  return undef;
		}
		elsif($value eq "off")
		{
	   our $testalarm = 0;
	   return undef;
		}
	}
	if($opt eq "sessionid") 
	{	  
		$hash->{session_id} = $value;
		return undef;	
	}
	
	
    #$hash->{STATE} = $bsms_gets{$opt} = $value;
   # start($hash);
    #readingsBeginUpdate($hash);
	#readingsBulkUpdate( $hash, "Test", "reading ok" );
	#readingsEndUpdate( $hash, 1 );

	#return "$opt set to $value. Try to get it.";
}


sub bsms_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	#my @devices =  split(/\,/,$hash->{devices});
	if($cmd eq "set") {
        if($attr_name eq "msisdn/Tel") {
        	our $hash->{msisdn} = $attr_value;
        	return undef; 	
				}
				elsif($attr_name eq "Intervall"){
					our $hash->{intervall} = $attr_value;
					return undef;
				}
				elsif($attr_name eq "Alarmdauer"){
					our $hash->{alarmdauer} = $attr_value;
					return undef;
				}
				
				
	}elsif($cmd eq "del") {
        if($attr_name eq "msisdn/Tel") {
        	our $hash->{msisdn} = "";
        	return undef; 	
				}
				elsif($attr_name eq "Intervall"){
					our $hash->{intervall} = "";
					return undef;
				}
				elsif($attr_name eq "Alarmdauer"){
					our $hash->{alarmdauer} = "";
					return undef;
				}
				#else 
				#{
		    #	return "Unknown attr $attr_name";
				#}
				
	}
	return undef;
}

1;

=pod
=begin html

<a name="bsms"></a>
<h3>bsms</h3>
<ul>
    <i>bsms</i> implements the Dashboard API from Blaulichtsms. 
    To use this modul your organization must use Blaulichtsms. See 
    <a href="https://blaulichtsms.net/">Blaulichtsms</a> for more information.
    <br><br>
    <a name="bsmsdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; bsms &lt;customerID&gt &lt;username&gt &lt;password&gt;</code>
        <br><br>
        Example: <code>define FWAlert bsms 165123 Dashboarduser 12345</code>
        <br><br>
        
    </ul>
    <br>
    
    <a name="bsmsset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;option&gt; &lt;value&gt;</code>
        <br><br>
        You can <i>set</i> the following options.
        <br><br>
        Options:
        <ul>
              <li><i>Testalarm</i> on|off<br>
                  Defaults to "off"</li>
              
        </ul>
    </ul>
    
    <a name="bsmsget"></a>
  	<b>Get</b> <ul>N/A</ul><br>
    
    <a name="bsmsattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        Attributes:
        <ul>
            <li><i>Alarmdauer</i> <br>
                The seconds how long is the duration of an activ alert.
                Default is "3600".
            </li>
            <li><i>Intervall</i> <br>
                The seconds where the module poll the BSMSapi.
                Default is "10".
            </li>
            
        </ul>
    </ul>
</ul>

=end html

=begin html_DE

<a name="bsms"></a>
<h3>bsms</h3>
<ul>
    <i>bsms</i> Fhem Modul f&uuml;r die Dashboard API von Blaulichtsms. 
    Um dieses Modul zu benutzen muss deine Organisation Blaulichtsms nutzen. Siehe 
    <a href="https://blaulichtsms.net/">Blaulichtsms</a> f&uuml;r mehr informationen.
    <br><br>
    <a name="bsmsdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; bsms &lt;customerID&gt &lt;username&gt &lt;password&gt;</code>
        <br><br>
        Example: <code>define FWAlert bsms 165123 Dashboarduser 12345</code>
        <br><br>
        
    </ul>
    <br>
    
    <a name="bsmsset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;option&gt; &lt;value&gt;</code>
        <br><br>
        You can <i>set</i> folgende set befehle gibt es.
        <br><br>
        Options:
        <ul>
              <li><i>Testalarm</i> on|off<br>
                  Defaults to "off"</li>
              
        </ul>
    </ul>
    
    <a name="bsmsget"></a>
  	<b>Get</b> <ul>N/A</ul><br>
    
    <a name="bsmsattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        
        <br><br>
        Attributes:
        <ul>
            <li><i>Alarmdauer</i> <br>
                Die Dauer eines Alarms in Sekunden
                Default is "3600".
            </li>
            <li><i>Intervall</i> <br>
                Der Abfrage Intervall von der Blaulichtsms API.
                Default is "10".
            </li>
            
        </ul>
    </ul>
</ul>

=end html_DE

=cut
