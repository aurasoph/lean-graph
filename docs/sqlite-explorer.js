// SQLite-based Dependency Explorer
// Uses sql.js to query SQLite databases in the browser

class SQLiteDependencyExplorer {
    constructor() {
        this.currentGraph = 'structures';
        this.currentMode = 'search';
        this.traversalDepth = 1;
        this.db = null;
        this.visibleNodes = new Set();
        this.visibleEdges = new Set();
        this.nodeDistances = new Map(); // Track distance for coloring
        this.activeNode = null;
        
        this.simulation = null;
        this.svg = null;
        this.container = null;
        
        this.init();
    }
    
    async init() {
        this.setupSVG();
        this.setupEventListeners();
        
        // Load sql.js
        await this.loadSQLJS();
        await this.loadGraph('structures');
        this.updateInstructions();
    }
    
    async loadSQLJS() {
        if (window.initSqlJs) return;
        
        // Load sql.js from CDN
        const script = document.createElement('script');
        script.src = 'https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.8.0/sql-wasm.js';
        document.head.appendChild(script);
        
        return new Promise((resolve) => {
            script.onload = async () => {
                window.SQL = await initSqlJs({
                    locateFile: file => `https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.8.0/${file}`
                });
                resolve();
            };
        });
    }
    
    setupSVG() {
        const container = d3.select('.graph-container');
        this.container = container;
        
        const svg = d3.select('svg');
        this.svg = svg;
        
        // Add arrow marker
        svg.append('defs').append('marker')
            .attr('id', 'arrowhead')
            .attr('viewBox', '-0 -5 10 10')
            .attr('refX', 20)
            .attr('refY', 0)
            .attr('orient', 'auto')
            .attr('markerWidth', 8)
            .attr('markerHeight', 8)
            .attr('xoverflow', 'visible')
            .append('svg:path')
            .attr('d', 'M 0,-5 L 10 ,0 L 0,5')
            .attr('fill', '#6c757d')
            .style('stroke', 'none');
        
        // Create groups for links and nodes
        this.linkGroup = svg.append('g').attr('class', 'links');
        this.nodeGroup = svg.append('g').attr('class', 'nodes');
        this.labelGroup = svg.append('g').attr('class', 'labels');
        
        // Setup zoom
        const zoom = d3.zoom()
            .scaleExtent([0.1, 4])
            .on('zoom', (event) => {
                this.linkGroup.attr('transform', event.transform);
                this.nodeGroup.attr('transform', event.transform);
                this.labelGroup.attr('transform', event.transform);
            });
        
        svg.call(zoom);
    }
    
    setupEventListeners() {
        // Graph selector buttons
        d3.selectAll('.graph-btn').on('click', (event) => {
            const btn = event.target;
            const graphType = btn.dataset.graph;
            
            d3.selectAll('.graph-btn').classed('active', false);
            d3.select(btn).classed('active', true);
            
            this.loadGraph(graphType);
        });
        
        // Mode selector buttons  
        d3.selectAll('.mode-btn').on('click', (event) => {
            const btn = event.target;
            const mode = btn.dataset.mode;
            
            d3.selectAll('.mode-btn').classed('active', false);
            d3.select(btn).classed('active', true);
            
            this.setMode(mode);
        });

        // Depth range slider
        const depthRange = d3.select('#depth-range');
        if (!depthRange.empty()) {
            depthRange.on('input', () => {
                const val = depthRange.node().value;
                this.traversalDepth = parseInt(val);
                d3.select('#depth-value').text(val);
                
                // If we have an active node, refresh the traversal
                if (this.currentMode === 'traversal' && this.activeNode) {
                    this.setActiveNode(this.activeNode);
                }
            });
        }
        
        // Search input
        const searchInput = d3.select('.search-input');
        const suggestions = d3.select('.suggestions');
        
        searchInput.on('input', () => {
            const query = searchInput.node().value.toLowerCase();
            if (query.length < 2) {
                suggestions.style('display', 'none');
                return;
            }
            
            this.showSuggestions(query);
        });
        
        searchInput.on('keydown', (event) => {
            if (event.key === 'Enter') {
                const query = searchInput.node().value;
                this.searchAndAdd(query);
                searchInput.node().value = '';
                suggestions.style('display', 'none');
            }
        });
        
        // Control buttons
        d3.selectAll('.control-btn').on('click', (event) => {
            const action = event.target.dataset.action;
            this.handleAction(action);
        });
        
        // Click outside to close suggestions
        d3.select('body').on('click', (event) => {
            if (!event.target.closest('.search-section')) {
                suggestions.style('display', 'none');
            }
        });
    }
    
    async loadGraph(graphType) {
        this.currentGraph = graphType;
        this.container.select('.loading').style('display', 'flex');
        this.container.select('.loading').text('Loading graph database...');
        
        try {
            // Load database
            this.container.select('.loading').text(`Loading ${graphType} database...`);
            const dbResponse = await fetch(`data/${graphType}.db`);
            
            if (!dbResponse.ok) {
                throw new Error(`Failed to load ${graphType}.db: ${dbResponse.status}`);
            }
            
            const dbBuffer = await dbResponse.arrayBuffer();
            const dbArray = new Uint8Array(dbBuffer);
            
            this.db = new SQL.Database(dbArray);
            
            this.container.select('.loading').style('display', 'none');
            this.container.select('.instructions').style('display', 'block');
            
            // Clear current view
            this.visibleNodes.clear();
            this.visibleEdges.clear();
            this.activeNode = null;
            this.render();
            
        } catch (error) {
            console.error('Error loading graph:', error);
            this.container.select('.loading').html(`
                <div class="error">
                    Error loading ${graphType} database: ${error.message}<br><br>
                    Make sure the database files exist and are accessible.
                </div>
            `);
        }
    }
    
    queryDB(sql, params = []) {
        if (!this.db) return [];
        try {
            const stmt = this.db.prepare(sql);
            if (params.length > 0) {
                stmt.bind(params);
            }
            const result = [];
            while (stmt.step()) {
                result.push(stmt.getAsObject());
            }
            stmt.free();
            return result;
        } catch (error) {
            console.error('SQL Error:', error, 'Query:', sql, 'Params:', params);
            return [];
        }
    }
    
    setMode(mode) {
        this.currentMode = mode;
        
        if (mode === 'search') {
            d3.select('#search-controls').style('display', 'block');
            d3.select('#traversal-controls').style('display', 'none');
            d3.select('#mode-info').text('Click nodes to build custom neighborhoods');
        } else {
            d3.select('#search-controls').style('display', 'none');
            d3.select('#traversal-controls').style('display', 'block');
            d3.select('#mode-info').text('Click nodes to set active and view neighbors (up to depth K)');
        }
    }
    
    showSuggestions(query) {
        const suggestions = d3.select('.suggestions');
        
        if (!this.db) {
            suggestions.style('display', 'none');
            return;
        }
        
        // Enhanced search with multiple strategies
        const matches = this.getSuggestedNodes(query);
        
        if (matches.length === 0) {
            suggestions.style('display', 'none');
            return;
        }
        
        suggestions.html('');
        matches.forEach(node => {
            const item = suggestions.append('div')
                .attr('class', 'suggestion-item')
                .on('click', () => {
                    this.addNode(node.id);
                    d3.select('.search-input').node().value = '';
                    suggestions.style('display', 'none');
                });
            
            // Highlight the match
            const nodeText = node.label || node.id;
            const highlighted = this.highlightMatch(nodeText, query);
            item.html(highlighted);
        });
        
        suggestions.style('display', 'block');
    }
    
    getSuggestedNodes(query) {
        const lowerQuery = query.toLowerCase();
        
        // Strategy 1: Exact prefix matches
        let exactMatches = this.queryDB(
            "SELECT id, label, 'exact' as match_type FROM nodes WHERE LOWER(id) LIKE ? LIMIT 3",
            [`${lowerQuery}%`]
        );
        
        // Strategy 2: Contains matches
        let containsMatches = this.queryDB(
            "SELECT id, label, 'contains' as match_type FROM nodes WHERE LOWER(id) LIKE ? AND LOWER(id) NOT LIKE ? LIMIT 4",
            [`%${lowerQuery}%`, `${lowerQuery}%`]
        );
        
        // Strategy 3: Word boundary matches
        let wordMatches = this.queryDB(
            "SELECT id, label, 'word' as match_type FROM nodes WHERE LOWER(id) LIKE ? OR LOWER(id) LIKE ? OR LOWER(id) LIKE ? LIMIT 3",
            [`%${lowerQuery.charAt(0).toUpperCase() + lowerQuery.slice(1)}%`, 
             `%.${lowerQuery}%`,
             `%_${lowerQuery}%`]
        );
        
        const allMatches = [...exactMatches, ...containsMatches, ...wordMatches];
        const uniqueMatches = Array.from(
            new Map(allMatches.map(item => [item.id, item])).values()
        );
        
        const priorityOrder = { 'exact': 1, 'word': 2, 'contains': 3 };
        return uniqueMatches
            .sort((a, b) => (priorityOrder[a.match_type] || 4) - (priorityOrder[b.match_type] || 4))
            .slice(0, 8);
    }
    
    highlightMatch(text, query) {
        const lowerText = text.toLowerCase();
        const lowerQuery = query.toLowerCase();
        if (lowerText.includes(lowerQuery)) {
            const idx = lowerText.indexOf(lowerQuery);
            return text.substring(0, idx) +
                   `<strong style="color: #0d6efd;">${text.substring(idx, idx + query.length)}</strong>` +
                   text.substring(idx + query.length);
        }
        return text;
    }
    
    searchAndAdd(query) {
        if (!this.db) return;
        const matches = this.queryDB(
            "SELECT id FROM nodes WHERE id = ? OR id LIKE ? LIMIT 1",
            [query, `%.${query}`]
        );
        if (matches.length > 0) {
            this.addNode(matches[0].id);
        } else {
            alert(`Node "${query}" not found`);
        }
    }
    
    addNode(nodeId, expandRelatives = true) {
        if (!this.db) return;
        const nodeExists = this.queryDB("SELECT id FROM nodes WHERE id = ?", [nodeId]);
        if (nodeExists.length === 0) return;
        
        this.visibleNodes.add(nodeId);
        if (expandRelatives) {
            if (this.currentMode === 'search') {
                this.expandNeighbors(nodeId);
            } else {
                this.setActiveNode(nodeId);
            }
        }
        this.render();
    }
    
    expandNeighbors(nodeId) {
        const parents = this.queryDB("SELECT source FROM edges WHERE target = ?", [nodeId]);
        parents.forEach(edge => {
            this.visibleNodes.add(edge.source);
            this.visibleEdges.add(`${edge.source}->${nodeId}`);
        });
        const children = this.queryDB("SELECT target FROM edges WHERE source = ?", [nodeId]);
        children.forEach(edge => {
            this.visibleNodes.add(edge.target);
            this.visibleEdges.add(`${nodeId}->${edge.target}`);
        });
    }
    
    setActiveNode(nodeId) {
        this.activeNode = nodeId;
        this.visibleNodes.clear();
        this.visibleEdges.clear();
        this.nodeDistances.clear();
        
        this.visibleNodes.add(nodeId);
        this.nodeDistances.set(nodeId, 0);
        
        // Multi-depth expansion using BFS
        let currentLevelNodes = [nodeId];
        for (let depth = 1; depth <= this.traversalDepth; depth++) {
            let nextLevelNodes = [];
            for (const node of currentLevelNodes) {
                // Get parents
                const parents = this.queryDB("SELECT source FROM edges WHERE target = ?", [node]);
                parents.forEach(edge => {
                    if (!this.visibleNodes.has(edge.source)) {
                        this.visibleNodes.add(edge.source);
                        this.nodeDistances.set(edge.source, depth);
                        nextLevelNodes.push(edge.source);
                    }
                    this.visibleEdges.add(`${edge.source}->${node}`);
                });
                
                // Get children
                const children = this.queryDB("SELECT target FROM edges WHERE source = ?", [node]);
                children.forEach(edge => {
                    if (!this.visibleNodes.has(edge.target)) {
                        this.visibleNodes.add(edge.target);
                        this.nodeDistances.set(edge.target, depth);
                        nextLevelNodes.push(edge.target);
                    }
                    this.visibleEdges.add(`${node}->${edge.target}`);
                });
            }
            currentLevelNodes = nextLevelNodes;
            if (currentLevelNodes.length === 0) break;
        }
        
        d3.select('#active-node-display').text(`Active: ${nodeId}`);
        this.render();
    }
    
    handleAction(action) {
        switch (action) {
            case 'center-view': this.centerView(); break;
            case 'clear':
                this.visibleNodes.clear();
                this.visibleEdges.clear();
                this.nodeDistances.clear();
                this.activeNode = null;
                d3.select('#active-node-display').text('Active: None');
                this.render();
                break;
        }
    }
    
    render() {
        if (!this.db || this.visibleNodes.size === 0) {
            d3.select('#graph-stats').text('0 nodes, 0 edges');
            this.linkGroup.selectAll('line').remove();
            this.nodeGroup.selectAll('circle').remove();
            this.labelGroup.selectAll('text').remove();
            return;
        }
        
        const nodeIds = Array.from(this.visibleNodes);
        const placeholders = nodeIds.map(() => '?').join(',');
        const nodes = this.queryDB(
            `SELECT id, label, full_name FROM nodes WHERE id IN (${placeholders})`,
            nodeIds
        );
        
        // Add coordinates from simulation if they exist
        nodes.forEach(n => {
            const existing = this.simulation?.nodes().find(sn => sn.id === n.id);
            if (existing) { n.x = existing.x; n.y = existing.y; }
        });

        const edges = this.queryDB(
            `SELECT source, target FROM edges 
             WHERE source IN (${placeholders}) AND target IN (${placeholders})`,
            [...nodeIds, ...nodeIds]
        );
        
        d3.select('#graph-stats').text(`${nodes.length} nodes, ${edges.length} edges`);
        
        if (!this.simulation) {
            this.simulation = d3.forceSimulation()
                .force('link', d3.forceLink().id(d => d.id).distance(100))
                .force('charge', d3.forceManyBody().strength(-300))
                .force('center', d3.forceCenter(600, 400))
                .force('collision', d3.forceCollide().radius(30));
        }
        
        const link = this.linkGroup.selectAll('line')
            .data(edges, d => `${d.source}->${d.target}`);
        link.exit().remove();
        const linkAll = link.enter().append('line').attr('class', 'link').merge(link);
        
        const node = this.nodeGroup.selectAll('circle')
            .data(nodes, d => d.id);
        node.exit().remove();
        const nodeEnter = node.enter().append('circle')
            .attr('class', 'node')
            .attr('r', 8)
            .call(d3.drag()
                .on('start', (event, d) => this.dragStart(event, d))
                .on('drag', (event, d) => this.dragging(event, d))
                .on('end', (event, d) => this.dragEnd(event, d)))
            .on('click', (event, d) => this.nodeClick(event, d));
        
        const nodeAll = nodeEnter.merge(node)
            .classed('active', d => d.id === this.activeNode)
            .attr('fill', d => {
                if (d.id === this.activeNode) return '#28a745';
                const dist = this.nodeDistances.get(d.id);
                if (dist === 1) return '#17a2b8';
                if (dist === 2) return '#ffc107';
                if (dist === 3) return '#fd7e14';
                return '#6c757d';
            });
        
        const label = this.labelGroup.selectAll('text')
            .data(nodes, d => d.id);
        label.exit().remove();
        const labelAll = label.enter().append('text').attr('class', 'node-label').merge(label)
            .text(d => d.label);
        
        this.simulation.nodes(nodes);
        this.simulation.force('link').links(edges);
        this.simulation.alpha(0.3).restart();
        
        this.simulation.on('tick', () => {
            linkAll.attr('x1', d => d.source.x).attr('y1', d => d.source.y)
                   .attr('x2', d => d.target.x).attr('y2', d => d.target.y);
            nodeAll.attr('cx', d => d.x).attr('cy', d => d.y);
            labelAll.attr('x', d => d.x).attr('y', d => d.y - 15);
        });
    }
    
    nodeClick(event, d) {
        event.stopPropagation();
        if (this.currentMode === 'search') {
            this.addNode(d.id, true);
        } else {
            this.setActiveNode(d.id);
        }
    }
    
    dragStart(event, d) {
        if (!event.active) this.simulation.alphaTarget(0.3).restart();
        d.fx = d.x; d.fy = d.y;
    }
    
    dragging(event, d) { d.fx = event.x; d.fy = event.y; }
    
    dragEnd(event, d) {
        if (!event.active) this.simulation.alphaTarget(0);
        d.fx = null; d.fy = null;
    }
    
    centerView() {
        const width = this.svg.node().clientWidth;
        const height = this.svg.node().clientHeight;
        this.svg.transition().duration(750).call(
            d3.zoom().transform,
            d3.zoomIdentity.translate(width / 2, height / 2).scale(1)
        );
    }
    
    updateInstructions() {
        const inst = d3.select('.instructions');
        if (this.currentMode === 'search') {
            inst.html('🖱️ <strong>Click</strong> nodes to expand • 🔍 <strong>Search</strong> to add nodes • 📌 <strong>Drag</strong> to move');
        } else {
            inst.html('🖱️ <strong>Click</strong> to set active node • ⚙️ <strong>Adjust K</strong> to see neighbors • 📌 <strong>Drag</strong> to move');
        }
    }
}

document.addEventListener('DOMContentLoaded', () => {
    window.explorer = new SQLiteDependencyExplorer();
});
