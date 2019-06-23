# NSCP_PA.PS1
# Author: snapier
# Date: 03-MAY-2019
# Monitor the service state for NSCP and notify nagios via
# NRDP (Hostcheck) for service state change processing.

    # Hostname in lowercase
    $myhost = "somehost"
    #$myHost = $env:COMPUTERNAME.ToLower()

    $nscpinfo = @()
    $nscpinfo += @(gwmi win32_service -filter "name LIKe 'nscp'")
    $nscpState = $nscpinfo.State

    #PerfData for the NSCP Service. NSCP is a critical service so I want the warnin to be at 99% up and critical to be 95%
    $nscpServicePData_warn = "98"
    $nscpServicePData_crit = "95"

    if($nscpState -ne "Running")
    {
    # If NSCP is not running, I'm not monitoring
    # Any state onter than running is a problem!

    # Mimic the formatting and content for the Host_check in NSCP
    $nscpServicemsg = "NSCP=(Not Running)"

    # Our "Displayed State"
    $nscpServiceDisplayState = "CRITICAL"

    # Our State to Return to Nagios
    $nscpServiceState = 1

    # Service PerfData
    $nscpServicePData = -1
 
    }
    elseif($nscpState -eq "Running")
    {

    # OK, NSCP Running! I'm monitoring things.
    # Mimic the formatting and content for the Host_check in NSCP
    $nscpServiceMsg = "NSCP=(Running)"

    # Our "Displayed State"
    $nscpServiceDisplayState = "OK"

    # Our State to Return to Nagios
    $nscpServiceState = 0

    # Service PerfData
    $nscpServicePData = 100

    }
    else
    {
    # NSCP is....
    # If the system fails to gather the information for NSCP
    # this should catch the failure and let us send an UNKNOWN
    # value with the error in the message.

    # Mimic the formatting and content for the Host_check in NSCP
    $nscpServiceMsg = "NSCP=(No Data)"

    # Our "Displayed State"
    $nscpServiceDisplayState = "UNKNOWN"

    # Our State to Return to Nagios
    $nscpServiceState = 2

    # Service PerfData
    $nscpServicePData = 0

    }

    $hostcheck = '{"checkresult": {"type": "host","checktype": "1"},"hostname": "'+$($myhost)+'","state": "'+$($nscpServiceState)+'","output":"'+$($nscpServiceDisplayState)+': '+$($nscpServiceMsg)+' | nscp='+$($nscpServicePData)+';'+$($nscpServicePData_warn)+';'+$($nscpServicePData_crit)+'"}'

    if($nscpState -ne "Stopped"){
        $lu_check_valid = "YES"
    }else{
        $lu_check_valid = "NO"
    } 

    if($nscpState -ne "Running"){
        $perfdata_check_valid = "NO"
    }else{
        $perfdata_check_valid = "YES"
    }

    #Get NSClient.Log file data
    $nscplog = @()
    $nscplog =  @(Get-Item "C:\Program Files\NSClient++\nsclient.log")

    # Get the last time the file was written too
    $ludt = Get-Date($nscplog.LastWriteTime)

    # Get the durration of time since the log file has been modified to now.
    $ludt_delta = (New-TimeSpan -Start ($ludt) -End (Get-Date))
    
    #convert the time delta to minutes so that we can evaluate the result
    $ludt_delta_min = $ludt_delta.Minutes

    #I have a very robust schedule for my NSClient timer, 2-minutes. If my log file has not been written to within 1-2 times
    #the duration of the timer then I want a warning. If the delta is double or greater my timer then I want a critical.
    if(($ludt_warn_delta_min -ge 3) -and ($ludt_warn_delta_min -lt 5)){
        $luState = "1"
        $ludStatus = "WARNING"
        $lumsg = "$($ludStatus): NSClient.log file nas not updated in ($($ludt_delta_min)) minute/s. LASTUPDATE=($($ludt)) | log-update-delta=$($ludt_delta_min);3;5;"
    }elseif($ludt_warn_delta_min -ge 5){
        $luState = "2"
        $ludStatus = "CRITICAL"
        $lumsg = "$($ludStatus): NSClient.log file nas not updated in ($($ludt_delta_min)) minute/s. LASTUPDATE=($($ludt)) | log-update-delta=$($ludt_delta_min);3;5;"
    }else{
        $luState = "0"
        $ludStatus = "OK"
        $lumsg = "$($ludStatus): NSClient.log updated($($ludt_delta_min)) minute/s ago. LASTUPDATE=($($ludt)) | log-update-delta=$($ludt_delta_min);3;5;"
    }

    # Build an array with the results for check_lastupdate.
    $loglastupdate = @($ludt,$ludt_delta_min,$ludStatus,$luState,$lumsg,$lu_check_valid)
    
    #echo "LASTLOGUPDATE = $($loglastupdate) `n"


    #the final variable is a the boolean for IS-VALID. If the NSCP service is not equal to stopped, the check
    #will be run as normal. If the value is NO, then the Unkoown value will be reutrned.
    if($loglastupdate['5'] -eq "YES"){
        # IF the state is not stopped, then we want to run our copmaritive check.
        $lastupdate_check = '{"checkresult": {"type": "service","checktype": "1"},"hostname": "'+$($myhost)+'", "servicename":"win--system--nscp--last-nsclient-log-updated-time", "state":"'+$($loglastupdate['3'])+'", "output":"'+$($loglastupdate['4'])+'"}'
    }else{
        # If the agent is stopped then there is no reason to run the comparitive check. To avoid noise in our incident
        # management system, we will set the state to unknown.
        $lastupdate_check = '{"checkresult": {"type": "service","checktype": "1"},"hostname": "'+$($myhost)+'", "servicename":"win--system--nscp--last-nsclient-log-updated-time", "state":"3", "output":"UNKNOWN: No Log Activity Expected NSCP=(Stopped). | last-update-delta=-1;3;5"}'
    }

    #echo "`nLASTUPDATECHECK_OUT = $($lastupdate_check) `n"


    #NSCP Process Performance Data
    $perfdata = @()
    $perfdata += @(Get-WmiObject -Class Win32_PerfFormattedData_PerfProc_Process -Filter "Name='nscp'")

    #We will only have perfdata if the service is running.
    if($nscpState -ne "Stopped"){
        $pDataState = 0
        $pDataStatus = "OK"
        $check_valid = "YES"
        # NSCP Is running We have Data
        $perfdataout = "$("ThreadCount="+$perfdata.ThreadCount+";") $("PageFileBytes="+$perfdata.PageFileBytes+";") $("PageFileBytesPeak="+$perfdata.PageFileBytesPeak+";") $("PoolNonpagedBytes="+$perfdata.PoolNonpagedBytes+";") $("PoolPagedBytes="+$perfdata.PoolPagedBytes+";") $("PrivateBytes="+$perfdata.PrivateBytes+";") $("PriorityBase="+$perfdata.PriorityBase+";") $("IOReadOperationsPersec="+$perfdata.IOReadOperationsPersec+";") $("PercentProcessorTime="+$perfdata.PercentProcessorTime+";") $("PercentUserTime="+$perfdata.PercentUserTime+";") $("PercentPrivilegedTime="+$perfdata.PercentPrivilegedTime+";")"
        $pDataMsg = "OK: NSCP=(Not Stopped) Performance Data=(TRUE) | "+$($perfdataout) 
    }else{
        # NO perfdata, so we need to zero the values
        $pDataState = 3
        $pDataStatus = "UNKNOWN"
        $check_valid = "NO"
        $perfdataout = "$("ThreadCount=0;") $("PageFileBytes=0;") $("PageFileBytesPeak=0;") $("PoolNonpagedBytes=0;") $("PoolPagedBytes=0;") $("PrivateBytes=0;") $("PriorityBase=0;") $("IOReadOperationsPersec=0;") $("PercentProcessorTime=0") $("PercentUserTime=0;") $("PercentPrivilegedTime=0")"
        #This is a non evaluated check so we will always send the OK state. The zero data points are included.
        $pDataMsg = "UNKNOWN: NSCP=(Stopped) Performance Data=(FALSE) | "+$($perfdataout)
    }

    #Build an array to hold the results
    $nscpperfdata = @($pDataState, $pDataStatus, $pDataMsg, $perfdataout, $perfdata_check_valid)

    #The final variable is a the boolean for IS-VALID. If the NSCP service is not equal to stopped, the check
    #will be run as normal. If the value is NO, then the Unkoown value will be reutrned.
    if($nscpperfdata['15'] -eq 'YES'){
        # IF the state is not stopped, then we want to return the collected data.
        $perfdata_check = '{"checkresult": {"type": "service","checktype": "1"},"hostname": "'+$($myhost)+'", "servicename":"win--system--nscp--all-process-perfdata", "state":"0", "output":"'+$($nscpperfdata['2'])+'"}'
    }else{
        # If the agent is stopped then there is no reason to run the comparitive check. To avoid noise in our incident
        # management system, we will set the state to unknown and we will send back a 0 for our data points
        $perfdata_check = '{"checkresult": {"type": "service","checktype": "1"},"hostname": "'+$($myhost)+'", "servicename":"win--system--nscp--all-process-perfdata", "state":"3", "output":"'+$($nscpperfdata['2'])+'"}'
    }

    #echo "NSCPPERFDATA_CHECK = $($perfdata_check)"

    # ----------------------------------
    # NRDP SETTINGS
    # ----------------------------------

    # NRDP Token (Change this to your configured token)
    $token = "token"

    # NRDP URL (Change this to your IP)
    $nrdpurl = "http://192.168.1.148/nrdp/"

 
    # ----------------------------------
    # HOSTCHECK AND JSONDATA
    # ----------------------------------

    $jsondata_open = 'JSONDATA={"checkresults":['
    $jsondata_close = ']}'

    #json post data
    $json = "$($jsondata_open) $($hostcheck), $($lastupdate_check), $($perfdata_check) $($jsondata_close)"

    # Formatting Sanity Check
    echo "`nJSONDATA = $($json) `n"

    #HTTP POST
    $post = @()
    $post += @(Invoke-WebRequest -UseBasicParsing "$($nrdpurl)?token=$($token)&cmd=submitcheck&$($json)" -Contenttype "application/json" -Method POST)

    #POST Status
    $result = $post.Content
    echo "NRDP = $($result) `n"
