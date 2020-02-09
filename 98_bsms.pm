package main;
#use strict;
#use warnings;
use JSON;
use LWP::UserAgent;
use DateTime::Format::Strptime qw(strptime);
use HttpUtils;

sub bsms_setr($$$);

####GLOBAL###
{
	our $alarms;
	our $testalarm = 0;
	our $hash;
}

my %bsms_sets =
(
  "Testalarm"					=> "textField",
# "sessionid"					=> "textField",
);
		
sub bsms_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'bsms_Define';
    $hash->{UndefFn}    = 'bsms_Undef';
    $hash->{SetFn}      = 'bsms_Set';
  	$hash->{NotifyFn}   = "bsms_Notify";
  	$hash->{AttrFn}     = 'bsms_Attr';
    $hash->{ReadFn}     = 'bsms_Read';

    $hash->{AttrList} =
    	#"msisdn/Tel ".
    	"Intervall ".
    	"Alarmdauer "
    	. $readingFnAttributes;
      
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
    $hash->{STATE} = "active";

    return bsms_main($hash);
}

sub bsms_get_session($){
	my ($hash, $def) = @_;
	
	my $name = $hash->{NAME};
	my $content = {   
									"customerId" => $hash->{customer_id},
									"username" => $hash->{username},
									"password" => $hash->{password},
								};
  my $jcontent = JSON->new->utf8->encode($content);
	my $param = {
								url        	=> "https://api.blaulichtsms.net/blaulicht/api/alarm/v1/dashboard/login",
								timeout    	=> 5,
								hash       	=> $hash,                                                                                 
								method     	=> "POST",                                                                                
								header     	=> "Content-Type: application/json",                            
								data				=> $jcontent,      
								callback  	=> \&bsms_get_session_response                                                                  	
							};

	HttpUtils_NonblockingGet($param);                                                                                     
}

sub bsms_get_session_response($){
	my ($param, $err, $data) = @_;
    
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	if($err ne ""){
		Log3 $name, 3, "error while requesting ".$param->{url}." - $err";                                               
	}
	elsif($data ne ""){
		my $message = $data;
		my $fromjson = from_json($message);
		my $obj = $fromjson->{"sessionId"};
		bsms_setr($hash, "sessionID", $obj);
		$hash->{session_id} = $obj;
		Log3 $name, 3, "$name: - successful session -- ID = $obj";   
	}
    
	return 1;
}

sub bsms_convert_time($){
	my ($obj) = @_;
	
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

sub bsms_get_alarms($){
	my ($hash, $def) = @_;
	
  my $name = $hash->{NAME};
  my $sessionnotnull = $hash->{session_id};
	unless ($sessionnotnull) { bsms_get_session($hash);}
	my $session = $hash->{session_id};	
	my $param = {
								url        	=> "https://api.blaulichtsms.net/blaulicht/api/alarm/v1/dashboard/".$session,
								timeout    	=> 5,
								hash       	=> $hash,                                                                                 
								method     	=> "GET",                                                                                 
								header     	=> "Content-Type: application/json",                               
								callback  	=> \&bsms_get_alarms_response                                                                  
                	
							};

	HttpUtils_NonblockingGet($param);                                                                                     
}

sub bsms_get_alarms_response($){
	my ($param, $err, $data) = @_;
	
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
    
  if($err ne ""){
  	Log3 $name, 3, "error while requesting ".$param->{url}." - $err";                                                   
    bsms_set_state($hash, "ERROR connection");
		bsms_get_alarms($hash);                                                 
	}
	elsif($data eq ""){
		Log3 $name, 3, "ERROR at requesting alarms! maybe invalid session ".$param->{url};
		bsms_set_state($hash, "Error session");
		bsms_get_session($hash);
	}
  elsif($data ne ""){  
  	my $message = $data;
		my $fromjson = from_json($message);	
		Log3 $name, 4, "$name: - content = $data";		
		our $alarms = $fromjson;                                        
  }
    
    return 1;
}

sub bsms_is_alarm($){
	my ($hash) = @_;
	
	my $name = $hash->{NAME};
	bsms_get_alarms($hash);
	my $duration = 3600;
	
	if($hash->{alarmdauer} > 0 ){
     $duration = $hash->{alarmdauer};
	}
	
	unless (our $alarms) { bsms_get_alarms($hash);}
	
	my $dt = DateTime->now;
	my $tslocal = $dt->epoch;
	my $obj = our $alarms->{"alarms"}[0]{"alarmDate"};
	my $txt = our $alarms->{"alarms"}[0]{"alarmText"};
	if ($obj eq ""){
		
		Log3 $name, 4, "$name: - Date is empty $obj";
		
	}
	else{

		my $time_lastalarm = bsms_convert_time($obj) ;
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

		bsms_setr($hash, "letzte_Alarm", $timestr);
		bsms_setr($hash, "Meldetext", $txt);
	
		if($timelastoffset >= $tslocal or our $testalarm == 1){
		
			bsms_setr($hash, 'Alarm', 'Alarm');
			bsms_set_state($hash, "Alarm");
			return 1;
			
		}else{
		
			bsms_setr($hash, "Alarm", "kein Alarm");
			bsms_set_state($hash, "running");
		
			return undef;
		}
		
	}
	
}

sub bsms_set_state($$) {
	my ($hash, $value) = @_;
	
	$hash->{STATE} = $value;
	return 1;
}

sub bsms_main($) {
	my ($hash) = @_;
	
	my $intervall = 30;
	my $session = $hash->{session_id};
	if( $hash->{intervall} > 0 ) {
     $intervall = $hash->{intervall};
	}
	my $timer = gettimeofday() + $intervall;
	my $start ="bsms_main";
	
	if ($session ne ""){
		
		bsms_is_alarm($hash);
	
	}
	else{
		
		bsms_get_session($hash)
		
	}
	
	our $hash = $hash;	
	RemoveInternalTimer($hash);
  InternalTimer($timer, $start, $hash,0);
}

sub bsms_setr ($$$) {
	my ($hash, $reading, $value) = @_;
	
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, $reading, $value);
	readingsEndUpdate( $hash, 1 );
	
	return 1;
}

sub bsms_Undef($$) {
	my ($hash, $arg) = @_;   
	RemoveInternalTimer($hash);
    
	return undef;
}

sub bsms_Notify($$){
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
	
}


sub bsms_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	if($cmd eq "set") {
      #  if($attr_name eq "msisdn/Tel") {
      #  	our $hash->{msisdn} = $attr_value;
      # 	return undef; 	
			#	}
				if($attr_name eq "Intervall"){
					our $hash->{intervall} = $attr_value;
					return undef;
				}
				elsif($attr_name eq "Alarmdauer"){
					our $hash->{alarmdauer} = $attr_value;
					return undef;
				}
				
				
	}elsif($cmd eq "del") {
        #if($attr_name eq "msisdn/Tel") {
        #	our $hash->{msisdn} = "";
        #	return undef; 	
				#}
				if($attr_name eq "Intervall"){
					our $hash->{intervall} = "";
					return undef;
				}
				elsif($attr_name eq "Alarmdauer"){
					our $hash->{alarmdauer} = "";
					return undef;
				}
				
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
