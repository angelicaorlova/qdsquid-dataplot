classdef DcData < TauData
% DcData        A class for parsing and fitting dc susceptibilities
%
%   obj = DcData(filename)
%   INPUT   filename:   (string)
%   OUTPUT  obj:        (object handle)
%
%   METHODS plotArrhenius           - Outputs an Arrhenius plot of the tau data
%           plotMoment              - Plots moment versus time
%           setTempRange(tempRange) - Sets the data selection range by temperature
%
%   PROPERTIES  Fits        - (table) Debye model fits of the input data over
%                             TempRange
%               TempRange   - Currently selected temperature range
%
%   This class automatically fits dc susceptibilities upon creation to a stretched
%   exponential.
%
%   Type `help Relaxation` for details on how to fit these data to a
%   relaxation model.

    methods
        function obj = DcData(filename)
            obj = obj@TauData(filename);
            
            obj.parseTauData(obj.TempRange);
            obj.fitTau();
        end
        
        function plotArrhenius(obj)
            % DcData.plotArrhenius
            %
            % See PlotHelper.setArrheniusAxes()
            
            if ~ismember('tau', obj.Fits.Properties.VariableNames)
                disp('Relaxation times not fitted.');
            else
                PlotHelper.setDefaults();
                scatter(1 ./ obj.Fits.Temperature, log(obj.Fits.tau), [], PlotHelper.dataColor(obj.Fits.Temperature), 'filled', '^');
                xlabel('1/T (K^{-1})'); ylabel('ln(\tau)');
            end
        end
        
        function plotMoment(obj)
            % DcData.plotMoment
            
            PlotHelper.setDefaults();
            for a = 1:length(obj.Fits.Temperature)
               rows = obj.Parsed.TemperatureRounded == obj.Fits.Temperature(a);
               scatter(obj.Parsed.Time(rows), obj.Parsed.Moment(rows), [], PlotHelper.dataColor(obj.Fits.Temperature(a)), 'filled');
               if ~isempty(obj.Fits)
                    plot(obj.Parsed.Time(rows), obj.Parsed.MomentCalc(rows), 'LineWidth', 2, 'Color', [0 0 0]);
               end
            end
            xlabel('Time (s)'); ylabel('Moment (emu mol^{-1})');
        end
        
        function setTempRange(obj, tempRange)
            % DcData.setTempRange(tempRange)
            % INPUT     (1x2 vector) temperature range to include for fitting
            
            obj.parseTauData(tempRange);
            obj.fitTau();
        end
    end
    
    methods (Hidden)
        function parseTauData(obj, tempRange)
            obj.Parsed                      = table(obj.Raw.Temperature_K_, 'VariableNames', {'Temperature'});
            obj.Parsed.TemperatureRounded   = round(obj.Parsed.Temperature / 0.05) * 0.05;
            obj.Parsed.Time                 = obj.Raw.TimeStamp_sec_;
            obj.Parsed.Field                = obj.Raw.MagneticField_Oe_;
            obj.Parsed.Moment               = (obj.Raw.DCMomentFreeCtr_emu_ ./ obj.Header.Moles); ...
                                                - (obj.Header.EicosaneXdm * obj.Header.EicosaneMoles .* obj.Parsed.Field) ...
                                                - (obj.Header.Xdm .* obj.Parsed.Field);
            
            if ~isnan(tempRange)
                toDelete = obj.Parsed.TemperatureRounded < tempRange(1) | obj.Parsed.TemperatureRounded > tempRange(2);
                obj.Parsed(toDelete,:) = [];
            end
            obj.TempRange = [min(obj.Parsed.TemperatureRounded), max(obj.Parsed.TemperatureRounded)];
            
            temps = unique(obj.Parsed.TemperatureRounded);
            for a = 1:length(temps)
                rows = obj.Parsed.TemperatureRounded == temps(a);
                obj.Parsed.Time(rows) = obj.Parsed.Time(rows) - min(obj.Parsed.Time(rows));
            end
        end
        
        function fitTau(obj)
            obj.Fits = array2table(unique(obj.Parsed.TemperatureRounded), 'VariableNames', {'Temperature'});
            
            opts = optimoptions('lsqcurvefit', 'Algorithm', 'trust-region-reflective', 'Display', 'off', 'FunctionTolerance', 1e-25, 'StepTolerance', 1e-25);
            x0 = [10, 1];
            lb = [1, 0.2];
            ub = [1e6, 1.7];
            
            for a = 1:length(obj.Fits.Temperature)
                rows = obj.Parsed.TemperatureRounded == obj.Fits.Temperature(a);
                
                [x0, ~, resid, ~, ~, ~, J] = ...
                    lsqcurvefit(@(b, x) obj.fitFunction(b, x, max(obj.Parsed.Moment(rows)) ,min(obj.Parsed.Moment(rows))), x0, obj.Parsed.Time(rows), obj.Parsed.Moment(rows), lb, ub, opts);
                obj.Parsed.MomentCalc(rows) = obj.fitFunction(x0, obj.Parsed.Time(rows), max(obj.Parsed.Moment(rows)), min(obj.Parsed.Moment(rows)));
                y = nlparci(x0, resid, 'Jacobian', J);
                
                obj.Fits.DataType(a, :) = 'DcData';
                obj.Fits.tau(a) = x0(1); obj.Fits.tauCi(a) = obj.Fits.tau(a) - y(1, 1);
                obj.Fits.beta(a) = x0(2); obj.Fits.betaCi(a) = obj.Fits.beta(a) - y(2, 1);
            end
        end
    end
    
    methods (Static, Access = private)
        function output = fitFunction(b, x, m0, mf)
            output = mf + (m0 - mf).*exp(-(x./b(1)).^b(2));
        end
    end
end