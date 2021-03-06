%% Stage1_rawextraction

%this script will grab the folder containing 1 fish and then process all of
%the files in the subfolders, aligning all the slices and then extracting
%seeds based on correlation and saving the output
%% clean up
clearvars
close all
Paths
%% Define the list of control fish so they are named as such

control_list = {'Imax10','Imax11','X2','X3','X4','X5','X6'};
%% Define miscellaneous constants

%define the target save path
% save_path_ori = 'C:\Clemens_suite\2020\pipeline_test\Stage1';
save_path_ori = fullfile(analysis_path,'Stage1');

%don't need this, just leave as is
skip_stim = [];
comb_vec = [];

% maximum allowed area for a seed
thres_area = 5;
%minimum seed area
thres_minarea = 3;

%define the amount of mode taking when aligning
mode_wind = 5;
%define whether to save files
save_var = 1;
%% Load the files and define paths

%get the folder where the image files are4
tar_path_all_pre = uipickfiles('FilterSpec','D:\Clemens_shared\_all_fish_raw');
% %extract all subfolders on that folder (deepest level)
% tar_path_all = path_sub_1(tar_path_all{1});

%allocate memory for the path list
tar_path_all = cell(size(tar_path_all_pre));
%for each one of the folders selected, get the subfolders
for subdir = 1:length(tar_path_all)
    tar_path_all{subdir} = path_sub_1(tar_path_all_pre{subdir});
    %get a vector with the dirs containing REP
    rep_dir = ~cellfun(@isempty,strfind(tar_path_all{subdir},'REP'));
    %if REP files are present, leave only those
    if sum(rep_dir) > 0
        tar_path_all{subdir} = tar_path_all{subdir}(rep_dir);
    end
end
%concatenate the full list of files
tar_path_all = vertcat(tar_path_all{:});
% %exclude the files with no REP in the same folder as REP files
% %get the files with REP first
% rep_files = ~cellfun(@isempty,strfind(tar_path_all,'REP'));
% %and another variable with the files without
% norep_files = ~rep_files;
% %get the number of rep files
% repf_num = sum(rep_files);
% %and the actual file names
% rep_list = tar_path_all(rep_files);
% %also the norep files
% norep_list = tar_path_all(norep_files);
% 
% %for all the rep files
% for repfs = 1:repf_num
%     %extract the rep from the file name
%     norep = strsplit(rep_list{repfs},'\');
%     norep = norep{end}(5:end);
%     %find the no rep string in the no rep list
%     isrep = norep_list(~cellfun(@isempty,strfind(norep_list,norep)));
%     %replace the file name in the main list with a 0
%     tar_path_all{strcmp(tar_path_all,isrep)} = false;
% end
% 
% %get rid of the zeros in the main list
% tar_path_all = tar_path_all(~cellfun(@islogical,tar_path_all)) ;

%get the number of experiments selected
num_exp = length(tar_path_all);
% %get a flag for pre and post for each file
% prepost_vec = ones(num_exp,1);
% %mark the post files with a 2
% prepost_vec(~cellfun(@isempty,strfind(tar_path_all,'Post'))) = 2;
% %get the name of the fish
% fish_name = strsplit(tar_path_all{1},'\');
% fish_name = fish_name{4};
% %create the target folders
% mkdir(save_path,fish_name)
% save_path_ori = fullfile(save_path,fish_name);
% mkdir(save_path_ori,'pre')
% save_cell = {fullfile(save_path_ori,'pre'),[]};
% if sum(prepost_vec==2)>0
%     mkdir(save_path_ori,'post')
%     save_cell{2} = fullfile(save_path_ori,'post');
% end
%% Run the main processing loop
%for all the experiments
info = cell(num_exp,1);
for exp_ind = 1:num_exp
    
    %get the path of the current experiment
    tar_path = tar_path_all{exp_ind};    
    %% And parse them based on their filenames
%     info{exp_ind} = parser_2(tar_path);
    [file_info,stim_num,rep_num,z_num,tar_files] = parser_2(tar_path);

    %using the first file, find out the number of time points in the trace
    first_info = imfinfo(fullfile(tar_path,tar_files{1}));
    time_num = length(first_info);
    %% Run the z section main for loop
    %allocate memory to store the seeds per z-section and their image
    seed_cell = cell(z_num,1);
    im_cell = cell(z_num,1);
    %also for the traces
    trace_cell = cell(z_num,1);
    %for the shifts
    shift_cell = cell(z_num,1);
    %and for the SNR
    % snr_mat = zeros(first_info(1).Height,first_info(1).Width,stim_num,z_num);
    snr_cell = cell(z_num,1);

    %for the averaged frames
    ave_frame = cell(z_num,1);

    %define the pre and post periods
    pre_time = false(time_num,1);
    pre_time(1:0.25*time_num) = 1;
    stim_time = false(time_num,1);
    stim_time(0.25*time_num+1:0.75*time_num) = 1;
    post_time = false(time_num,1);
    post_time(0.75*time_num+1:end) = 1;

    %allocate memory to store the correlation stack and the shuff one
    corr_stack = zeros(first_info(1).Height,first_info(1).Width,z_num);
    % corr_shuff = zeros(first_info(1).Height,first_info(1).Width,z_num);
    %allocate memory for a cutoff vector
    seed_cutoff = ones(z_num,1);

    %define the number of total frames per z (not counting reps)
    total_frames = stim_num*time_num;

    %if it's the first iteration
    if exp_ind == 1
        %activate the parallel pool
        gcp = parpool;
    end
    %for all the z sections
    parfor z = 1:z_num
        %% Calculate dfof, compress replicates, accumulate and align
        [singlez_mat,shift_cell{z},ave_frame{z},snr_mat] = ...
            aligner_7(tar_path,tar_files,stim_num,rep_num,file_info,pre_time,z...
            ,skip_stim,mode_wind);

        %NaN the edges of the image to avoid spurious correlations
        singlez_mat(1:5,:,:) = NaN;
        singlez_mat(:,1:5,:) = NaN;
        singlez_mat(end-4:end,:,:) = NaN;
        singlez_mat(:,end-4:end,:) = NaN;
%         %Eliminate NaNs from the dfof calculation with zeros (from the -100
%         %subtraction
%         singlez_mat(isnan(singlez_mat)) = 0;
        %% Run the correlation software
        %only in the frames that were averaged or moded. Don't do it on the
        %ones added at the end from the exclusion
        corr_stack(:,:,z) = Stack_process_1(singlez_mat,0);
        %% Determine the seed threshold based on the shuff stack

        %linearize the correlation frame for percentile 
        lin_corr = corr_stack(:,:,z);
        seed_cutoff(z) = prctile(lin_corr(:),95);
        %print the resulting value
        fprintf(strcat('The cutoff for z =',num2str(z),' is:',num2str(seed_cutoff(z)),'\n'))
        %% Seeding function

        %define the seeding parameters

        %minimum correlation to start a seed
        thres_seed = seed_cutoff(z);
        %minimum correlation to expand a seed
        thres_nb = seed_cutoff(z);
        %run the actual seeding algorithm
        [seed_cell{z},im_cell{z}] = Seeder_1(corr_stack(:,:,z),...
            thres_seed,thres_nb,thres_area,thres_minarea);
        %% Use the seeds to process all of the slices in this z-section for signals
        %get the seed number in this z section
        seed_num = size(seed_cell{z},2);

        %allocate memory for storing the traces
        seed_currz = zeros(seed_num,total_frames);
        %and for the snr output
        snr_currz = zeros(seed_num,stim_num);
        %initialize a frame counter
        frame_counter = 1;
        %for all the frames
        for frames = 1:total_frames        
            %load the current frame
            curr_frame = singlez_mat(:,:,frames);
            %for all the seeds in this z section
            for seed = 1:seed_num
                %add the intensities for each frame and store in the seed
                seed_currz(seed,frame_counter) = mean(curr_frame(seed_cell{z}(seed).pxlist));
            end
            %update the frame counter
            frame_counter = frame_counter + 1;
        end

        %also calculate the snr for each seed by averaging across the snr of
        %its voxels

        %for all the seeds in this z section
        for seed = 1:seed_num
            %for all the stimuli
            for stim = 1:stim_num
                %load the frame for the current stim
                curr_stim = snr_mat(:,:,stim);
                %calculate the average of the seed voxels
                snr_currz(seed,stim) = mean(curr_stim(seed_cell{z}(seed).pxlist));
            end
        end
        %store the reshaped version in the output cell
        trace_cell{z} = reshape(seed_currz,[seed_num,time_num,stim_num]); 
        %and the snr of the seeds in this z
        snr_cell{z} = snr_currz;
    end

    %turn the average cell into a stack
    ave_stack = cat(3,ave_frame{:});
    %NaN the edges of the image since they are not used
    ave_stack(1:5,:,:) = NaN;
    ave_stack(:,1:5,:) = NaN;
    ave_stack(end-4:end,:,:) = NaN;
    ave_stack(:,end-4:end,:) = NaN;
    %if it's the last iteration
    if exp_ind == num_exp
        %delete the parallel pool (closing it)
        delete(gcp)
    end
    %% Configure the z information

    %concatenate the trace cell info
    all_trace = vertcat(trace_cell{:});

    %also for the seed_cell
    seed_concat = horzcat(seed_cell{:})';

    %create a vector with the z of each seed
    z_seed = zeros(size(all_trace,1),1);
    %initialize a counter
    z_count = 1;
    %for all the zs
    for z = 1:z_num
        %get the number of seeds in this z
        z_seednum = size(trace_cell{z},1);
        %turn the corresponding positions to the z in the map vector
        z_seed(z_count:z_seednum+z_count-1) = z;
        %update the counter
        z_count = z_count + z_seednum;
    end
    %format the input matrix for saving
    conc_trace = reshape(all_trace,size(all_trace,1),size(all_trace,2)*size(all_trace,3));
    %% Save analysis output
    if save_var == 1

        %define the root of the save name
        [ori_folder,ori_name,~] = fileparts(tar_path);
        
        %get the fish and pre-Post
        ori_folder = strsplit(ori_folder,'\');
        fish_id = ori_folder{4};
        prepost_id = ori_folder{5};
        if isempty(strfind(prepost_id,'Pre'))
            if any(strcmp(fish_id,control_list))
                prepost_id = 'control';
            else
                prepost_id = 'post';
            end
        else
            prepost_id = 'pre';
        end
        
        %assemble the folder path
        save_path = fullfile(save_path_ori,fish_id,prepost_id);
        %if it doesn't exist, create it
        if ~isdir(save_path)
            mkdir(save_path)
        end
        
%         %and load the save path
%         save_path = save_cell{prepost_vec(exp_ind)};
        
        

        % save the trace cell extracted from the fluo data
        save_trace = strcat(ori_name,'_traces.mat');
        save(fullfile(save_path,save_trace),'conc_trace','trace_cell','seed_cell',...
            'shift_cell','ave_stack','seed_concat','z_seed','snr_cell')

        %and save variables for plotting and such
        save_plot = strcat(ori_name,'_plot.mat');
        save(fullfile(save_path,save_plot),'time_num','stim_num')
        %save the average stack for the dataset, including the seed
        %positions
        %define the saving path
        fig_path = save_path;
%         %parse the file name
%         [~,ori_name,~] = fileparts(tar_path);
        %add the file name extension
        fig_name = strcat(ori_name,'_anato.tif');
        %assemble the final path
        fig_full = fullfile(fig_path,fig_name);
        %for all the z slices
        for z = 1:z_num
            %calculate the fused image with the average stack and the seeds
            %plotted
            C = imfuse(ave_stack(:,:,z),im_cell{z});
            %write the images
            if z ==1
                imwrite(C,fig_full,'tif','Resolution',size(C),'WriteMode','overwrite')
            else
                imwrite(C,fig_full,'tif','Resolution',size(C),'WriteMode','append')
            end
        end
    end
end