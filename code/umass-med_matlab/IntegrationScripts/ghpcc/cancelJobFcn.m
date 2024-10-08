function OK = cancelJobFcn(cluster, job)
%CANCELJOBFCN Cancels a job on LSF
%
% Set your cluster's IntegrationScriptsLocation to the parent folder of this
% function to run it when you cancel a job.

% Copyright 2010-2017 The MathWorks, Inc.

% Store the current filename for the errors, warnings and dctSchedulerMessages
currFilename = mfilename;
if ~isa(cluster, 'parallel.Cluster')
    error('parallelexamples:GenericLSF:SubmitFcnError', ...
        'The function %s is for use with clusters created using the parcluster command.', currFilename)
end
if cluster.HasSharedFilesystem
    error('parallelexamples:GenericLSF:SubmitFcnError', ...
        'The submit function %s is for use with nonshared filesystems.', currFilename)
end
% Get the information about the actual cluster used
data = cluster.getJobClusterData(job);
if isempty(data)
    % This indicates that the job has not been submitted, so return true
    dctSchedulerMessage(1, '%s: Job cluster data was empty for job with ID %d.', currFilename, job.ID);
    OK = true;
    return
end
try
    clusterHost = data.RemoteHost;
    remoteJobStorageLocation = data.RemoteJobStorageLocation;
    makeLocationUnique = false;
catch err
    ex = MException('parallelexamples:GenericLSF:FailedToRetrieveRemoteParameters', ...
        'Failed to retrieve remote parameters from the job cluster data.');
    ex = ex.addCause(err);
    throw(ex);
end
remoteConnection = getRemoteConnection(cluster, clusterHost, remoteJobStorageLocation, makeLocationUnique);
try
    jobIDs = data.ClusterJobIDs;
catch err
    ex = MException('parallelexamples:GenericLSF:FailedToRetrieveJobID', ...
        'Failed to retrieve clusters''s job IDs from the job cluster data.');
    ex = ex.addCause(err);
    throw(ex);
end

% Only ask the cluster to cancel the job if it is hasn't reached a terminal
% state.
erroredJobs = cell(size(jobIDs));
jobState = job.State;
if ~(strcmp(jobState, 'finished') || strcmp(jobState, 'failed'))
    % Get the cluster to delete the job
    for ii = 1:length(jobIDs)
        jobID = jobIDs{ii};
        commandToRun = sprintf('source /etc/profile.d/lsf.sh && bkill "%d"', jobID);
        dctSchedulerMessage(4, '%s: Canceling job on cluster using command:\n\t%s.', currFilename, commandToRun);
        % Keep track of all jobs that were not canceled successfully - either through
        % a bad exit code or if an error was thrown.  We'll report these later on.
        try
            % Execute the command on the remote host.
            [cmdFailed, cmdOut] = remoteConnection.runCommand(commandToRun);
        catch err
            cmdFailed = true;
            cmdOut = err.message;
        end
        if cmdFailed
            erroredJobs{ii} = jobID;
            dctSchedulerMessage(1, '%s: Failed to cancel job %d on cluster.  Reason:\n\t%s', currFilename, jobID, cmdOut);
        end
    end
end

% Only stop mirroring if we are actually mirroring
if remoteConnection.isJobUsingConnection(job.ID)
    dctSchedulerMessage(5, '%s: Stopping the mirror for job %d.', currFilename, job.ID);
    try
        remoteConnection.stopMirrorForJob(job);
    catch err
        warning('parallelexamples:GenericLSF:FailedToStopMirrorForJob', ...
            'Failed to stop the file mirroring for job %d.\nReason: %s', ...
            job.ID, err.getReport);
    end
end
% Now warn about those jobs that we failed to cancel.
erroredJobs = erroredJobs(~cellfun(@isempty, erroredJobs));
if ~isempty(erroredJobs)
    warning('parallelexamples:GenericLSF:FailedToCancelJob', ...
        'Failed to cancel the following jobs on the cluster:\n%s', ...
        sprintf('\t%d\n', erroredJobs{:}));
end
OK = isempty(erroredJobs);
