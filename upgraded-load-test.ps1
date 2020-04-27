[CmdletBinding()]

param([Int32]$users, [string]$url, [Int32] $iterations, [double] $max_average_seconds, [bool] $bypass_cache)

$InformationPreference = "Continue"

$user_code = {
    param ($user, $url_1, $auth, $show_result)

    $user_start = Get-Date
	$200_count = 0;

	# Create the request
	$HTTP_Request = [System.Net.WebRequest]::Create("$($url_1)")
	
	$HTTP_Request.Timeout = 600000;
	#$HTTP_Request.Headers["Authorization"] = $auth
	$HTTP_Request.Headers["User-Agent"] = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
	
	$request_start = Get-Date
	
	# Get the response
	try{
		$HTTP_Response = $HTTP_Request.GetResponse()
	}catch [Exception]{
		Write-Verbose $_.Exception.GetType().FullName, $_.Exception.Message
	}
	
	$request_end = Get-Date
    
    If($verbose -eq  $true){
        $reqstream = $http_response.getresponsestream()
	    $sr = new-object system.io.streamreader $reqstream
	    $result = $sr.readtoend()
	
	    Write-Verbose "Web Result: $($result)."
    }	

	# Get the HTTP as a interger
	$HTTP_Status = [int]$HTTP_Response.StatusCode

	
	If (($HTTP_Status -eq 200)) {
		$200_count = 1;
	}
	Else {
		$HTTP_Status = -1
	}
	
	# # Clean up and close the request.
	$HTTP_Response.Close()
	
    $user_stop = Get-Date

    $duration = $request_end - $request_start

    $response_object = @{
        'User' = $user;
        'Status' = $HTTP_Status;
        'Duration' = $duration;
        'Url' = $url_1;
    }

    return $response_object;
}

function Iteration {
    param([Int32] $current_iteration)
    Write-Information ""
    Write-Information "##--Iteration #$($current_iteration)."
    Write-Information ""
    # Create a runspace pool where $maxConcurrentJobs is the 
    # maximum number of runspaces allowed to run concurrently    
    $pool = [runspacefactory]::CreateRunspacePool(1,$users)
    $pool.ThreadOptions  = "Default"

    # Open the runspace pool (very important)
    $pool.Open()

    $runspaces = @()

    $pdp_urls = "/shop/1198038/11017034",      #One Variant PDP (Very Small PDP)
    "/shop/1236313/11165561",  #Four variants PDP (Small PDP)
    "/shop/1232495/11160198", #Eight variants PDP (Medium PDP)
    "/shop/1207894/11695592",              #Fifteen variants PDP (Large PDP)
    "/shop/1204218/11692890"    #Twenty seven variants PDP (Very Large PDP)

    $count = ($current_iteration - 1) * $users;

    (1 .. $users) | % { 

        $current_pdp_url = $pdp_urls[$count%$pdp_urls.length]
        $count ++

        If($bypass_cache -eq $true){
            $current_pdp_url = $current_pdp_url + "?bypasscache=true"
        }

	    $runspace = [PowerShell]::Create()
        $null = $runspace.AddScript($user_code)
        $null = $runspace.AddArgument($_)
	    $null = $runspace.AddArgument("$($url)$($current_pdp_url)")
        $null = $runspace.AddArgument($auth)
        $null = $runspace.AddArgument($show_error_details)
        $runspace.RunspacePool = $pool

	    # BLOCK 4: Add runspace to runspaces collection and "start" it
        # Asynchronously runs the commands of the PowerShell object pipeline
        $runspaces += [PSCustomObject]@{ Pipe = $runspace; Status = $runspace.BeginInvoke() }
    }

    #echo "##--Waiting for users to finish..."
    #echo ""

    # # BLOCK 5: Wait for runspaces to finish

    $total_success = 0;
    $total_errors = 0;
    $accumulated_durations = 0

    $acumulated_duration_seconds = 0
    $longest_running_user = New-TimeSpan -Seconds 0
    $shortest_running_user = New-TimeSpan -Days 30

    while ($runspaces.Status -ne $null)
    {
        $completed = $runspaces | Where-Object { $_.Status.IsCompleted -eq $true }
        foreach ($runspace in $completed)
        {
            $response_object = $runspace.Pipe.EndInvoke($runspace.Status)

            Write-Information "--User #$($response_object.User) Status: $($response_object.Status) Duration: $($response_object.Duration) Url: $($response_object.Url)" 
        
            If($response_object.Status -eq 200){
                $total_success += 1
            }else{
                $total_errors += 1
            }

            $acumulated_duration_seconds += [TimeSpan]::Parse($response_object.Duration).TotalSeconds

            If($response_object.Duration -lt $shortest_running_user){
                $shortest_running_user = $response_object.Duration
            }

            If($response_object.Duration -gt $longest_running_user){
                $longest_running_user = $response_object.Duration
            }

            $runspace.Status = $null
        }
    }

    $average_duration_seconds = [math]::Round($acumulated_duration_seconds/$users, 4)

    $results_object = [pscustomobject]@{
        'Errors' = $total_errors;
        'Successes' = $total_success;
        'LongestRequest' = $longest_running_user;
        'ShortestRequest' = $shortest_running_user;
        'AverageRequestSeconds' = $average_duration_seconds;
    }

    $pool.Close() 
    $pool.Dispose()

    return $results_object
}


 Write-Output ""

 If($bypass_cache -eq $true){
    Write-Output "#Starting load test with $($iterations) iteration(s) and $($users) user(s) hitting $($url) bypassing the pdp cache."
 }else{
    Write-Output "#Starting load test with $($iterations) iteration(s) and $($users) user(s) hitting $($url)."
 }

$test_total_successes = 0
$test_total_errors = 0
$test_tota_acumulated_duration_seconds = 0

$start = Get-Date
$iteration_start = 0
$iteration_end = 0

for ($i=1; $i -le $iterations; $i++) {
    $iteration_start = Get-Date

    $iteration_result = Iteration -current_iteration $i

    $iteration_end = Get-Date

    $test_total_successes += $iteration_result.Successes
    $test_total_errors += $iteration_result.Errors
    $test_tota_acumulated_duration_seconds += $iteration_result.AverageRequestSeconds

     Write-Output ""

     Write-Output "#-----------------Iteration #$($i) Results-----------------------------#"
     If($i -ne 1){
        Write-Output ""
     }
     
     Write-Output $iteration_result

     Write-Output "#-----------------Iteration #$($i) ($($iteration_end - $iteration_start)).-----------------#"

     Write-Output ""
}

$test_tota_average_duration_seconds = [math]::Round($test_tota_acumulated_duration_seconds/$iterations, 4)

$test_totals_results_object = [pscustomobject]@{
        'Errors' = $test_total_errors;
        'Successes' = $test_total_successes;
        'Average Request (Secs)' = $test_tota_average_duration_seconds;
}

$stop = Get-Date

Write-Output ""

Write-Output "#-----------------Overall Test Results-----------------------------#"

Write-Output ""

Write-Output $test_totals_results_object

Write-Output "#-----------------Load Test End ($($stop - $start))-----------------#"

Write-Output ""

If($test_totals_results_object.Errors -gt 0){
    Write-Error "Response Errors Found."
}

If($test_tota_average_duration_seconds -gt $max_average_seconds){
    Write-Error "The Average Response Time ($($test_tota_average_duration_seconds)) exceeds the max time expected: $($max_average_seconds)."
}