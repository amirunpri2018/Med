% function [noduleRecall, recallRate, thresholdedMask, centerInds] = ComputeThresholdRecallRate(scoreMapFolder, uniqueMaskPath, threshScoreMask, windowDim,removeSmallNodFlag)
%CHANGE THE WAY POSITIVE DETECTION IS DONE, S.T. INSTEAD OF COMPARING WITH
%NODULE LOCATION, WE COMPARE AGAINST BOX 28X28X8 CENTERED ON NODULE?
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
scoreMapFolder = '/raida/apezeshk/temp/DeepMed/scoreMaps';
uniqueMaskPath = '/raida/apezeshk/lung_dicom_dir/';
threshScoreMask = 0.9;
windowDim = [15, 15, 6];
removeSmallNodFlag = 1;
truthMode = 'nodule'; %'nodule' or 'patch'; if nodule, peak coordinate should fall within nodule bbox for detection; if patch, it should fall within patch centered at nodule centroid (depends on training patch size)
patchSize = [28, 28, 8]; %only used if truthMode=='patch'
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
files = dir(scoreMapFolder);
files(1:2) = [];
noduleCounter = 0;
noduleRecall = {};
for jj = 1:length(files)
        fprintf('Loading No.%d testing subject (total %d).\n', jj,length(files));
        currentMapName = files(jj).name;
        
        currentScoreMap = load(fullfile(scoreMapFolder, currentMapName));
        currentScoreMap = currentScoreMap.vect;
        
        %do 3d max suppression for current case
        [maxmap, maxidx] = minmaxfilt(currentScoreMap, windowDim, 'max', 'same');
        bool = (currentScoreMap == maxmap);
        currentMapMaxSupp = single(bool).*currentScoreMap;
        
        [thresholdedMask, centerInds] = GetCandidatesFromScoreMap(currentMapMaxSupp, threshScoreMask);    

        folderComp = regexprep(currentMapName, '_', '/');
        folderComp = regexprep(folderComp, '.mat', '');
        currentUniquePath = fullfile(uniqueMaskPath, folderComp, ['uniqueStats_' currentMapName]);
        uniqueMaskData = load(currentUniquePath);
%         noduleMask = uniqueMaskData.allMaxRadiologistMsk;
        uniqueStats = uniqueMaskData.uniqueStats;        
        
        currentNegativeInd = 1:size(centerInds,1); %initialize; list of all row numbers for peaks in centerInds; later these will be reduced by taking out the row numbers corresponding to positive peaks

        for m = 1:length(uniqueStats)
                current_avgPrincipalAxisLength = uniqueStats(m).avgPrincipalAxisLength;
                %                         if current_avgPrincipalAxisLength == 0:
                %                                 current_minx = uniqueStats(m).minX -1; %extend the min/max in x,y to make sure the thing gets obliterated
                %                                 current_maxx = uniqueStats(m).maxX + 1;
                %                                 current_miny = uniqueStats(m).minY - 1;
                %                                 current_maxy = uniqueStats(m).maxY + 1;
                %                                 current_minz = uniqueStats(m).minZ; %somehow z just does not need to be fixed
                %                                 current_maxz = uniqueStats(m).maxZ;
                %                                 %swap x,y to get matrix coordinates bc matlab x,y are image coordinates
                %                                 noduleMask(current_miny:current_maxy, current_minx:current_maxx, current_minz:current_maxz) = 0;
                %                         end
                if removeSmallNodFlag == 1 %whether to ignore the <3mm nodules from the master nodule mask
                        if current_avgPrincipalAxisLength == 0
                                continue
                        end
                end
                noduleCounter = noduleCounter + 1;        
                
                noduleRecall{noduleCounter, 1} =  currentMapName;
                noduleRecall{noduleCounter, 2} = m; %this is the nodule unique tag for that case
                noduleRecall{noduleCounter, 3} = 0; %initialize; later, if this nodule is detected in thresholded max suppressed score map, will be set to 1
                if strcmp(truthMode, 'nodule')
                        bounds_minx = uniqueStats(m).minX; %note these are matlab image coordinates, so x,y are flipped relative to row,column
                        bounds_maxx = uniqueStats(m).maxX;
                        bounds_miny = uniqueStats(m).minY;
                        bounds_maxy = uniqueStats(m).maxY;
                        bounds_minz = uniqueStats(m).minZ;
                        bounds_maxz = uniqueStats(m).maxZ;
                        
                elseif strcmp(truthMode, 'patch')
                        current_centroidx = uniqueStats(m).avgVolCentroidX;%note these are matlab image coordinates, so x,y are flipped relative to row,column
                        current_centroidy = uniqueStats(m).avgVolCentroidY;
                        current_centroidz = uniqueStats(m).avgVolCentroidZ;
                        bounds_minx = floor(current_centroidx - patchSize(1)/2);%note these are matlab image coordinates, so x,y are flipped relative to row,column
                        bounds_maxx = ceil(current_centroidx + patchSize(1)/2);
                        bounds_miny = floor(current_centroidy - patchSize(2)/2);
                        bounds_maxy = ceil(current_centroidy + patchSize(2)/2);
                        bounds_minz = floor(current_centroidz - patchSize(3)/2);
                        bounds_maxz = ceil(current_centroidz + patchSize(3)/2);                        
                end      
                currentNoduleCheck = ismember(centerInds(:,2), bounds_minx:bounds_maxx) & ismember(centerInds(:,1), bounds_miny:bounds_maxy) & ismember(centerInds(:,3), bounds_minz:bounds_maxz);
                currentNoduleMatchInd = find(currentNoduleCheck); %row indices of peak points that fall within bounds of current nodule
                currentNegativeInd = setdiff(currentNegativeInd, currentNoduleMatchInd); %sequentially take out row indices of peaks that match a nodule in current case
                if ~isempty(find(currentNoduleCheck))
                        noduleRecall{noduleCounter, 3} = 1;
                end
                
        end

        disp(['Number of center peaks in current map: ' num2str(size(centerInds, 1))]);
%         save([cand_path num2str(jj) '_cand.mat'],'center');
end

recallRate = length(find([noduleRecall{:,3}]))/size(noduleRecall,1);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% if you want to get rid of large constant areas that occue in the corners
% of many CT slices, you can use the code below to eliminate the large
% areas in each slice according to a size threshold;
% zxc = currentMapMaxSupp > 0; %make a binary version that can be input to bwlabel and regionprops
% area_thresh = 30; %threshold for area of objects in each slice; anything larger will get eliminated
% for i = 1:size(currentMapMaxSupp, 3)        
%         qwe = bwlabel(zxc(:,:,i)); 
%         s_qwe = regionprops(qwe, 'ConvexArea'); 
%         areas_qwe =[s_qwe(:).ConvexArea]; %vector of areas of objects in current slice
%         labelsToRemove = find(areas_qwe>area_thresh);
%         if length(labelsToRemove)>0
%                 for j = 1:length(labelsToRemove)
%                         qwe(qwe==labelsToRemove(j)) = 0;
%                         zxc(:,:,i) = qwe;
%                 end
%         end
% end
% currentMapMaxSupp(~zxc) = 0; %set objects that are larger than threshold to zero
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%









