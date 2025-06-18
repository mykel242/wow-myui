-- VirtualScrollMixin.lua
-- Reusable virtual scrolling system for performance optimization

local addonName, addon = ...

-- ============================================================================
-- VIRTUAL SCROLL MIXIN
-- ============================================================================

local VirtualScrollMixin = {}
addon.VirtualScrollMixin = VirtualScrollMixin

-- Default configuration
local DEFAULT_CONFIG = {
    LINES_PER_CHUNK = 500,        -- Lines loaded per chunk
    BUFFER_CHUNKS = 2,            -- Buffer chunks above/below visible area  
    MIN_LINES_FOR_VIRTUAL = 1000, -- Only virtualize if more than this many lines
    TIMER_INTERVAL = 0.1,         -- Scroll monitoring interval (100ms)
    SCROLL_THRESHOLD = 10,        -- Minimum scroll change to trigger updates
    LINE_HEIGHT = 12,             -- Approximate line height for calculations
}

-- ============================================================================
-- MIXIN FUNCTIONS
-- ============================================================================

-- Create a new instance of the virtual scroll mixin
function VirtualScrollMixin:new()
    local instance = {}
    setmetatable(instance, { __index = VirtualScrollMixin })
    return instance
end

-- Initialize virtual scrolling for a frame
-- frame: The container frame
-- scrollFrame: The ScrollFrame
-- editBox: The EditBox/FontString that displays content  
-- config: Optional config overrides
function VirtualScrollMixin:Initialize(frame, scrollFrame, editBox, config)
    if not frame or not scrollFrame or not editBox then
        error("VirtualScrollMixin requires frame, scrollFrame, and editBox")
    end
    
    -- Store references
    self.parentFrame = frame
    self.scrollFrame = scrollFrame
    self.editBox = editBox
    self.config = config and self:MergeConfig(DEFAULT_CONFIG, config) or DEFAULT_CONFIG
    
    -- Initialize state
    self.state = {
        isActive = false,
        totalLines = 0,
        totalChunks = 0,
        loadedChunks = {},
        fullStructure = nil,
        headerLines = {},
        footerLines = {},
        timer = nil,
        lastScrollOffset = 0
    }
    
    -- Set up scroll monitoring
    self:SetupScrollMonitoring()
    
    addon:Debug("VirtualScrollMixin initialized for %s", frame:GetName() or "Unknown")
end

-- Merge configuration tables
function VirtualScrollMixin:MergeConfig(default, override)
    local merged = {}
    for k, v in pairs(default) do
        merged[k] = v
    end
    for k, v in pairs(override) do
        merged[k] = v
    end
    return merged
end

-- Set up scroll position monitoring
function VirtualScrollMixin:SetupScrollMonitoring()
    local function checkScrollPosition()
        if self.parentFrame and self.parentFrame:IsShown() and self.state.isActive then
            local currentOffset = self.scrollFrame:GetVerticalScroll()
            if math.abs(currentOffset - self.state.lastScrollOffset) > self.config.SCROLL_THRESHOLD then
                self.state.lastScrollOffset = currentOffset
                self:OnScrollChanged(currentOffset)
            end
        end
    end
    
    -- Start monitoring when frame is shown
    self.parentFrame:HookScript("OnShow", function()
        if self.state.timer then
            self.state.timer:Cancel()
        end
        if self.state.isActive then
            self.state.timer = C_Timer.NewTicker(self.config.TIMER_INTERVAL, checkScrollPosition)
        end
    end)
    
    -- Stop monitoring when hidden
    self.parentFrame:HookScript("OnHide", function()
        if self.state.timer then
            self.state.timer:Cancel()
            self.state.timer = nil
        end
    end)
end

-- Activate virtual scrolling with content
-- contentLines: Array of strings to display
-- headerLines: Optional array of header lines (always visible)
-- footerLines: Optional array of footer lines (always visible)
function VirtualScrollMixin:SetContent(contentLines, headerLines, footerLines)
    if not contentLines or #contentLines == 0 then
        self:Deactivate()
        return
    end
    
    local totalContentLines = #contentLines
    
    -- Check if virtual scrolling is needed
    if totalContentLines < self.config.MIN_LINES_FOR_VIRTUAL then
        self:DisplayTraditional(contentLines, headerLines, footerLines)
        return
    end
    
    -- Activate virtual scrolling
    self.state.isActive = true
    self.state.totalLines = totalContentLines
    self.state.totalChunks = math.ceil(totalContentLines / self.config.LINES_PER_CHUNK)
    self.state.loadedChunks = {}
    self.state.headerLines = headerLines or {}
    self.state.footerLines = footerLines or {}
    
    -- Create full structure with placeholders
    self:CreateVirtualStructure(contentLines)
    
    -- Load initial chunks
    self:EnsureChunkLoaded(1)
    
    -- Start scroll monitoring if frame is visible
    if self.parentFrame:IsShown() then
        if self.state.timer then
            self.state.timer:Cancel()
        end
        self.state.timer = C_Timer.NewTicker(self.config.TIMER_INTERVAL, function()
            if self.parentFrame and self.parentFrame:IsShown() and self.state.isActive then
                local currentOffset = self.scrollFrame:GetVerticalScroll()
                if math.abs(currentOffset - self.state.lastScrollOffset) > self.config.SCROLL_THRESHOLD then
                    self.state.lastScrollOffset = currentOffset
                    self:OnScrollChanged(currentOffset)
                end
            end
        end)
    end
    
    addon:Debug("Virtual scrolling activated: %d lines, %d chunks", totalContentLines, self.state.totalChunks)
end

-- Create virtual structure with placeholders
function VirtualScrollMixin:CreateVirtualStructure(contentLines)
    local structure = {}
    
    -- Add header lines
    for _, line in ipairs(self.state.headerLines) do
        table.insert(structure, line)
    end
    
    -- Add placeholders for all content lines
    for i = 1, #contentLines do
        table.insert(structure, string.format("[Loading line %d...]", i))
    end
    
    -- Add footer lines  
    for _, line in ipairs(self.state.footerLines) do
        table.insert(structure, line)
    end
    
    self.state.fullStructure = structure
    self.state.contentLines = contentLines
    self.state.headerLineCount = #self.state.headerLines
    
    -- Set initial content and height
    local fullContent = table.concat(structure, "\n")
    self.editBox:SetText(fullContent)
    self.editBox:SetHeight(#structure * self.config.LINE_HEIGHT)
end

-- Display content traditionally (no virtual scrolling)
function VirtualScrollMixin:DisplayTraditional(contentLines, headerLines, footerLines)
    self:Deactivate()
    
    local allLines = {}
    
    -- Add header
    if headerLines then
        for _, line in ipairs(headerLines) do
            table.insert(allLines, line)
        end
    end
    
    -- Add content
    for _, line in ipairs(contentLines) do
        table.insert(allLines, line)
    end
    
    -- Add footer
    if footerLines then
        for _, line in ipairs(footerLines) do
            table.insert(allLines, line)
        end
    end
    
    local fullContent = table.concat(allLines, "\n")
    self.editBox:SetText(fullContent)
    self.editBox:SetHeight(#allLines * self.config.LINE_HEIGHT)
    
    addon:Debug("Traditional display: %d total lines", #allLines)
end

-- Handle scroll position changes
function VirtualScrollMixin:OnScrollChanged(offset)
    if not self.state.isActive then
        return
    end
    
    local scrollHeight = self.scrollFrame:GetVerticalScrollRange()
    local scrollPercent = scrollHeight > 0 and (offset / scrollHeight) or 0
    
    local targetChunk = math.floor(scrollPercent * self.state.totalChunks) + 1
    targetChunk = math.max(1, math.min(targetChunk, self.state.totalChunks))
    
    self:EnsureChunkLoaded(targetChunk)
end

-- Ensure a chunk and its buffer are loaded
function VirtualScrollMixin:EnsureChunkLoaded(chunkIndex)
    if not self.state.isActive then
        return
    end
    
    local bufferSize = self.config.BUFFER_CHUNKS
    local startChunk = math.max(1, chunkIndex - bufferSize)
    local endChunk = math.min(self.state.totalChunks, chunkIndex + bufferSize)
    
    local needsUpdate = false
    
    -- Load missing chunks in range
    for i = startChunk, endChunk do
        if not self.state.loadedChunks[i] then
            self:LoadChunk(i)
            needsUpdate = true
        end
    end
    
    -- Unload chunks outside range to save memory
    for loadedChunk, _ in pairs(self.state.loadedChunks) do
        if loadedChunk < startChunk or loadedChunk > endChunk then
            self.state.loadedChunks[loadedChunk] = nil
            needsUpdate = true
        end
    end
    
    if needsUpdate then
        self:UpdateDisplay()
    end
end

-- Load a specific chunk
function VirtualScrollMixin:LoadChunk(chunkIndex)
    if not self.state.isActive or not self.state.contentLines then
        return
    end
    
    local startIdx = (chunkIndex - 1) * self.config.LINES_PER_CHUNK + 1
    local endIdx = math.min(startIdx + self.config.LINES_PER_CHUNK - 1, #self.state.contentLines)
    
    local chunkLines = {}
    for i = startIdx, endIdx do
        table.insert(chunkLines, self.state.contentLines[i])
    end
    
    self.state.loadedChunks[chunkIndex] = chunkLines
    
    -- Update the full structure with loaded chunk
    if self.state.fullStructure then
        for i = 1, #chunkLines do
            local globalLineIndex = self.state.headerLineCount + startIdx + i - 1
            if globalLineIndex <= #self.state.fullStructure then
                self.state.fullStructure[globalLineIndex] = chunkLines[i]
            end
        end
    end
end

-- Update the display with current loaded content
function VirtualScrollMixin:UpdateDisplay()
    if not self.state.isActive or not self.state.fullStructure then
        return
    end
    
    local newContent = table.concat(self.state.fullStructure, "\n")
    self.editBox:SetText(newContent)
end

-- Deactivate virtual scrolling
function VirtualScrollMixin:Deactivate()
    self.state.isActive = false
    
    if self.state.timer then
        self.state.timer:Cancel()
        self.state.timer = nil
    end
    
    -- Clear state
    self.state.loadedChunks = {}
    self.state.totalChunks = 0
    self.state.totalLines = 0
    self.state.fullStructure = nil
    self.state.contentLines = nil
end

-- Get status information
function VirtualScrollMixin:GetStatus()
    return {
        isActive = self.state.isActive,
        totalLines = self.state.totalLines,
        totalChunks = self.state.totalChunks,
        loadedChunks = self:GetLoadedChunkCount(),
        hasTimer = self.state.timer ~= nil
    }
end

-- Get number of loaded chunks
function VirtualScrollMixin:GetLoadedChunkCount()
    local count = 0
    for _ in pairs(self.state.loadedChunks) do
        count = count + 1
    end
    return count
end

return VirtualScrollMixin