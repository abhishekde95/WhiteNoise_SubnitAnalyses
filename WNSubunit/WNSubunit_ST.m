% WNSubunit - Use only when you have selected a mask for isolating the
% subunits. Make sure you run the program once before performning the
% permutation test.
% Differs from 'WNSubunit.m'. It accepts the spatio-temporal receptive
% field as one vector. Does not treat the vector frame by frame basis which
% 'WNSubunit.m' does.
%
% Author - Abhishek De, 07/02/2015
tic;
clearvars;
close all;
echo off;
plot_counter = 1; % defining a counter to keep a track on the index of the figure

% ********************************************************************************
%                Declaring the local and global variables here
% ********************************************************************************

[stro,filename,no_subunit] = library(); % get one file from the library
plot_counter = plot_cone_monitor_fund(stro,plot_counter);

% Declaring global variables 
global spikename maskidx spikeidx nstixperside ngammasteps seedidx nframesidx stimonidx muidxs sigmaidxs
global msperframe ntrials maxT xx yy M 
spikename = getSpikenum(stro);
maskidx = strcmp(stro.sum.rasterCells(1,:), 'subunit_mask');
spikeidx = strcmp(stro.sum.rasterCells(1,:),spikename);
nstixperside = stro.sum.exptParams.nstixperside;
ngammasteps = 2^16; % 65536
seedidx = strcmp(stro.sum.trialFields(1,:),'seed');
nframesidx = strcmp(stro.sum.trialFields(1,:),'num_frames');
stimonidx = strcmp(stro.sum.trialFields(1,:),'stim_on');
muidxs = [find(strcmp(stro.sum.trialFields(1,:),'mu1')), ...
    find(strcmp(stro.sum.trialFields(1,:),'mu2')), ...
    find(strcmp(stro.sum.trialFields(1,:),'mu3'))];
sigmaidxs = [find(strcmp(stro.sum.trialFields(1,:),'sigma1')), ...
    find(strcmp(stro.sum.trialFields(1,:),'sigma2')), ...
    find(strcmp(stro.sum.trialFields(1,:),'sigma3'))];
msperframe = 1000/stro.sum.exptParams.framerate;
ntrials = size(stro.trial,1);
maxT = 15; % this represents the temporal part in the spatiotemporal receptive field
xx = linspace(stro.sum.exptParams.gauss_locut/1000, stro.sum.exptParams.gauss_hicut/1000,ngammasteps); % xx represents the probabilities. For more info, have a look at the MATLAB 'norminv' function.
yy = norminv(xx'); % defining norminv to extract the values for which the cdf values range between gauss_locut and gauss_hicut


% Obtaining the M matrix, code extracted from Greg, fitting a cubic spline
% using the command 'spline'. 'SplineRaw' only availabe through
% psychtoolbox which I currently don't have now.
fundamentals = stro.sum.exptParams.fundamentals; % CONE FUNDAMENTALS: L,M,S
fundamentals = reshape(fundamentals,[length(fundamentals)/3,3]); %1st column - L, 2nd- M, 3rd- S 
mon_spd = stro.sum.exptParams.mon_spd; % MONITOR SPECTRAL DISTRIBUTION IN R,G,B
mon_spd = reshape(mon_spd,[length(mon_spd)/3, 3]);
mon_spd = spline([380:4:780], mon_spd', [380:5:780]); % fitting a cubic spline
M = fundamentals'*mon_spd'; % matrix that converts RGB phosphor intensites to L,M,S cone fundamentals
M = inv(M');


% Determine when the mask changed in order to determine from what trials we started our experiment to study 
% the computation of the subunits which we are interested in.
mask_changes = 1;
all_masks = stro.ras(:,maskidx);
for k = 2:ntrials
    if isequal(all_masks{k}, all_masks{k-1}) %|| all(all_masks{k} == 0) && any(isnan(all_masks{k-1}))
        continue
    else
        mask_changes = [mask_changes k-1 k]; %#ok<AGROW>
    end
end

% Each column of `mask_changes` holds the start and end trial index where each
% mask was used. For example, the subunits A and B relevant to my project were added on trial number 69.
mask_changes = reshape([mask_changes ntrials], 2, []);
% disp(stro.ras{mask_changes(1,2),4}); % displays the time when the mask was selected
temp = [];

for i = 1:size(mask_changes,2)
    if strcmp('N072215002.nex',filename)
        temp = [temp, mask_changes(:,i);];
    elseif (mask_changes(2,i) - mask_changes(1,i) > 2)
        temp = [temp, mask_changes(:,i);];
    end
end
mask_changes = temp;

% Ad-hoc chnages to some of the nex files
if strcmp('N050415001.nex',filename)
    % file-specific changes of the masking trials
    mask_changes = user_defined_mask_changes(mask_changes,[2 3]);
elseif strcmp('N061515001.nex',filename)
    mask_changes = user_defined_mask_changes(mask_changes,[3 4]);
else
end
if isfield(stro.sum.exptParams,'nrepframes')
    if ~isnan(stro.sum.exptParams.nrepframes)
        nvblsperstimupdate = stro.sum.exptParams.nrepframes;
    else
        nvblsperstimupdate = 1;
    end
else
    nvblsperstimupdate = 1;
end

%**************************************************************************
%  Plotting the results before the subunit selection, white noise pixel
%  stimulus
%**************************************************************************
[plot_counter] = WNpixelplot(stro,plot_counter,mask_changes(:,1),'WNSubunit_ST');

%%
% ******************************************************************************************
%  This is the meat of the analysis for generating the spike triggered covariance matrix.
%  Modes 1,2 and 3 code perform the analysis only for the the subunits. The modes 4,5 and 6 
%  perform the same analysis but consider background as an additional subunit.
% ******************************************************************************************

mode_steps = [1 2]; 
% 1 - calculate the STA and the PCs
% 2 - projects the subunit stimuli onto the STAs and the PCs
% 3 - projects the high dimensional pixelated stimuli onto the STAs and the PCs,
% 4 - does the same thing as 1 but includes background too, 
% 5 - does the same thing as step 2 but includes the background as a subunit, 
% 6 - does the same thing as step 3 but includes the background as one of the basis vectors

mask_changes_idx = [2 2 1 3 3 1]; 
% 1 - white noise pixel stimulus
% 2 - subunit white noise stimulus w/o background
% 3 - subunit white noise stimulus w background as a subunit

prompt = 'Project along multiple directions?(Y/N)';
str = input(prompt,'s');
if ((strcmp('Y',str) || strcmp('y',str)))
   flag = 1;
else
    flag = 0;
end
% 0 - just project onto 'return_vec'
% 1 - project onto 'new_vec' (PC1 and STA) 

for mode = mode_steps
    % Only takes trials which have subunits selected on them. The selected trials can be accessed in 'mask_changes' 
    trial_span = mask_changes(:,mask_changes_idx(mode));
    for mask_span = trial_span 
        if  (mod(mode,3) == 1)
            % Just store enough space to accomodate the 9 frames of the basis vector
            st_mask = stro.ras{trial_span(1),maskidx}; % subunit mask                    
            st_mask(st_mask == 0) = Inf;
            [stIdxs,~,~] = unique(st_mask); % now the Infs map to nsubunits+1
            num_subunits = length(stIdxs)-any(isinf(stIdxs)); % nsubunits, like subunits A and B     
            STCOV_st('init', {num_subunits 3 maxT});
            
        elseif (mod(mode,3) == 2)
            % define basis vectors so that the stimuli can be projected onto it
            initargs = define_basis_vec(nrandnums_perchannel,stro,basis_vec,new_vec,flag);
            STPROJmod('init',initargs); % initialising the STPROJmod
        elseif (mod(mode,3) == 0)
            STPROJmod('init',initargs); % initialising the STPROJmod
        end
        
        for k = mask_span(1):mask_span(2)
            nframes = stro.trial(k,nframesidx);
            if (nframes == 0) 
                continue; 
            end
            seed = stro.trial(k,seedidx);
            mu = stro.trial(k,muidxs)/1000;
            sigma = stro.trial(k,sigmaidxs)/1000;
            
            % org_mask tells u if u have updated the mask or not. If org_mask is non-zero it means at this particular trial
            % u have selected the subunits and need to analyse its computation 
            org_mask = stro.ras{k,maskidx};
            
            if any(org_mask)
                org_mask(org_mask == 0) = Inf;
                [subunitIdxs,~,mask] = unique(org_mask); % now the Infs map to nsubunits+1
                nrandnums_perchannel = length(subunitIdxs)-any(isinf(subunitIdxs)); % nsubunits, like subunits A and B
                mask = [mask; mask+max(mask); mask+2*max(mask)]; %#ok<AGROW>
            else
                nrandnums_perchannel = nstixperside^2; % In this case, it is the 100 pixels which are flickering when no subunits are selected
            end
            
            % assuming Gaussian gun noise only, random number generator
            % routine as a mexfile (getEJrandnums.mexw64)
            invnormcdf = bsxfun(@plus, bsxfun(@times, yy, sigma), mu);
            randnums = getEJrandnums(3*nrandnums_perchannel*nframes, seed); % random numbers for 300 x 9 pixels
            % This is the extracted colors for subunits/pixels using the seed number
            randnums = reshape(randnums, 3*nrandnums_perchannel, nframes);
            for gun = 1:3
                idxs = (1:nrandnums_perchannel)+nrandnums_perchannel*(gun-1);
                randnums(idxs,:) = reshape(invnormcdf(randnums(idxs,:)+1,gun),[length(idxs) nframes]);
            end
             
            rgbs = randnums; 
            t_stimon = stro.trial(k, stimonidx);
            spiketimes = (stro.ras{k,spikeidx}-t_stimon)*1000; % observing spiketimes in milliseconds
%             frametimes = linspace(0, nframes*msperframe, nframes)+(msperframe/2)';
            frametimes = linspace(0, nframes*msperframe*nvblsperstimupdate, nframes)+(msperframe*nvblsperstimupdate/2)';
            % Deleting the spikes taking place before the first 9 frames as I need to look at the 9 preceding frames
            spiketimes(spiketimes < maxT*msperframe) = [];
            % Deleting the spikes that take place after the stimulus was
            % removed as it would imply that these spikes do not result from
            % the stimulus shown on the screen
            spiketimes(spiketimes > frametimes(end)) = [];
            n = hist(spiketimes, frametimes);
            if (mod(mode,3) == 1)
                % need to make some modifications here
                STCOV_st(rgbs(:),n);
            else
                STPROJmod(rgbs(:),n);  
                
            end
        end
        if (mod(mode,3) == 1)
            % Plot the STA and PCs if mode = 1,4
            [ch,new_vec, basis_vec, plot_counter,subunits,sub_rgb_idx] = compute_spatio_temp_basis_vec(plot_counter,nrandnums_perchannel,mask,flag,mode);
        elseif (mod(mode,3) == 2)
            % Calculate the projection values of the stimuli on the white noise subunit basis vectors
            [plot_counter,nbins,nbins1] = compute_projection_val(plot_counter,mode,subunits,1,1,flag,ch);
        elseif (mod(mode,3) == 0)
            % Calculate the projection values of the stimuli on the white noise basis vectors  
            [plot_counter,~,~] = compute_projection_val(plot_counter,mode,subunits,nbins,nbins1,flag,ch);
        end
    end
end

%------------------------------------------------------------
%       Significance Testing for PC1: Permutation Test
%------------------------------------------------------------
prompt1 = 'Do u want to run the permutation test? (Y/N)';
str1 = input(prompt1,'s');
if ((strcmp('Y',str1) || strcmp('y',str1)))
   feval('permutation_test',stro,mask_changes,plot_counter);
end
toc;

%**************************************************************************
%  Ask the user if he/she is interested in running the program once more
%**************************************************************************
prompt = 'Do u want to run the program again? (Y/N)';
str = input(prompt,'s');
if ((strcmp('Y',str) || strcmp('y',str)))
   eval('WNSubunit');
end


