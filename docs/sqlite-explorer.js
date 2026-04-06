// SQLite-based Dependency Explorer
// Uses sql.js to query SQLite databases in the browser

class SQLiteDependencyExplorer {
    constructor() {
        this.currentGraph = 'structures';
        this.currentMode = 'search';
        this.db = null;
        this.visibleNodes = new Set();
        this.visibleEdges = new Set();
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
            // Check if running on GitHub Pages (no large files available)
            const isGitHubPages = window.location.hostname.includes('github.io');
            
            if (isGitHubPages && (graphType === 'type-deps' || graphType === 'proof-deps')) {
                // Show message for unavailable large graphs on GitHub Pages
                this.container.select('.loading').html(`
                    <div class="error">
                        <strong>${graphType} graph not available on GitHub Pages</strong><br><br>
                        Large graphs (${graphType === 'type-deps' ? '412MB' : '1.8GB'}) require local setup.<br><br>
                        <strong>For complete experience:</strong><br>
                        1. Clone repository: <code>git clone https://github.com/aurasoph/lean-graph.git</code><br>
                        2. Run locally: <code>cd lean-graph/web-explorer && python3 -m http.server 8000</code><br>
                        3. Open: <code>http://localhost:8000</code>
                    </div>
                `);
                return;
            }
            
            // Load database (works for all graphs locally)
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
            d3.select('#mode-info').text('Click to build custom neighborhoods • *Large graphs require local setup');
        } else {
            d3.select('#search-controls').style('display', 'none');
            d3.select('#traversal-controls').style('display', 'block');
            d3.select('#mode-info').text('Click nodes to traverse • *Large graphs require local setup');
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
            
            // Highlight the match with different display based on match type
            const nodeText = node.label || node.id;
            const highlighted = this.highlightMatch(nodeText, query);
            item.html(highlighted);
        });
        
        suggestions.style('display', 'block');
    }
    
    getSuggestedNodes(query) {
        const lowerQuery = query.toLowerCase();
        
        // Strategy 1: Exact prefix matches (highest priority)
        let exactMatches = this.queryDB(
            "SELECT id, label, 'exact' as match_type FROM nodes WHERE LOWER(id) LIKE ? LIMIT 3",
            [`${lowerQuery}%`]
        );
        
        // Strategy 2: Contains matches for common math terms
        let containsMatches = this.queryDB(
            "SELECT id, label, 'contains' as match_type FROM nodes WHERE LOWER(id) LIKE ? AND LOWER(id) NOT LIKE ? LIMIT 4",
            [`%${lowerQuery}%`, `${lowerQuery}%`]
        );
        
        // Strategy 3: Word boundary matches (e.g., "Add" matches "AddCommGroup")
        let wordMatches = this.queryDB(
            "SELECT id, label, 'word' as match_type FROM nodes WHERE LOWER(id) LIKE ? OR LOWER(id) LIKE ? OR LOWER(id) LIKE ? LIMIT 3",
            [`%${lowerQuery.charAt(0).toUpperCase() + lowerQuery.slice(1)}%`, 
             `%.${lowerQuery}%`,
             `%_${lowerQuery}%`]
        );
        
        // Combine results, removing duplicates and prioritizing
        const allMatches = [...exactMatches, ...containsMatches, ...wordMatches];
        const uniqueMatches = Array.from(
            new Map(allMatches.map(item => [item.id, item])).values()
        );
        
        // Sort by relevance: exact > word boundary > contains
        const priorityOrder = { 'exact': 1, 'word': 2, 'contains': 3 };
        const result = uniqueMatches
            .sort((a, b) => {
                const priorityA = priorityOrder[a.match_type] || 4;
                const priorityB = priorityOrder[b.match_type] || 4;
                return priorityA - priorityB;
            })
            .slice(0, 8); // Limit to 8 suggestions
            
        return result;
    }
    
    highlightMatch(text, query) {
        const lowerText = text.toLowerCase();
        const lowerQuery = query.toLowerCase();
        
        if (lowerText.includes(lowerQuery)) {
            const startIndex = lowerText.indexOf(lowerQuery);
            const endIndex = startIndex + query.length;
            
            return text.substring(0, startIndex) +
                   `<strong style="color: #0d6efd;">${text.substring(startIndex, endIndex)}</strong>` +
                   text.substring(endIndex);
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
        
        // Check if node exists
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
        // Add parent nodes (incoming edges)
        const parents = this.queryDB(
            "SELECT source FROM edges WHERE target = ?", 
            [nodeId]
        );
        parents.forEach(edge => {
            this.visibleNodes.add(edge.source);
            this.visibleEdges.add(`${edge.source}->${nodeId}`);
        });
        
        // Add child nodes (outgoing edges) 
        const children = this.queryDB(
            "SELECT target FROM edges WHERE source = ?",
            [nodeId]
        );
        children.forEach(edge => {
            this.visibleNodes.add(edge.target);
            this.visibleEdges.add(`${nodeId}->${edge.target}`);
        });
    }
    
    setActiveNode(nodeId) {
        this.activeNode = nodeId;
        
        // In traversal mode, show only this node and its k=1 neighbors
        this.visibleNodes.clear();
        this.visibleEdges.clear();
        
        this.visibleNodes.add(nodeId);
        this.expandNeighbors(nodeId);
        
        d3.select('#active-node-display').text(`Active: ${nodeId}`);
        this.render();
    }
    
    handleAction(action) {
        if (!this.db || !this.activeNode) return;
        
        switch (action) {
            case 'expand-parents':
                const parents = this.queryDB(
                    "SELECT source FROM edges WHERE target = ?", 
                    [this.activeNode]
                );
                parents.forEach(edge => {
                    this.visibleNodes.add(edge.source);
                    this.visibleEdges.add(`${edge.source}->${this.activeNode}`);
                });
                this.render();
                break;
            
            case 'expand-children':
                const children = this.queryDB(
                    "SELECT target FROM edges WHERE source = ?",
                    [this.activeNode]
                );
                children.forEach(edge => {
                    this.visibleNodes.add(edge.target);
                    this.visibleEdges.add(`${this.activeNode}->${edge.target}`);
                });
                this.render();
                break;
            
            case 'center-view':
                this.centerView();
                break;
            
            case 'clear':
                this.visibleNodes.clear();
                this.visibleEdges.clear();
                this.activeNode = null;
                d3.select('#active-node-display').text('Active: None');
                this.render();
                break;
        }
    }
    
    render() {
        if (!this.db || this.visibleNodes.size === 0) {
            d3.select('#graph-stats').text('0 nodes, 0 edges');
            return;
        }
        
        // Get node data from database
        const nodeIds = Array.from(this.visibleNodes);
        const placeholders = nodeIds.map(() => '?').join(',');
        const nodes = this.queryDB(
            `SELECT id, label, full_name FROM nodes WHERE id IN (${placeholders})`,
            nodeIds
        );
        
        // Get edge data
        const edges = this.queryDB(
            `SELECT source, target FROM edges 
             WHERE source IN (${placeholders}) AND target IN (${placeholders})`,
            [...nodeIds, ...nodeIds]
        );
        
        // Update stats
        d3.select('#graph-stats').text(`${nodes.length} nodes, ${edges.length} edges`);
        
        // Create or update simulation
        if (!this.simulation) {
            this.simulation = d3.forceSimulation()
                .force('link', d3.forceLink().id(d => d.id).distance(100))
                .force('charge', d3.forceManyBody().strength(-300))
                .force('center', d3.forceCenter(600, 400))
                .force('collision', d3.forceCollide().radius(30));
        }
        
        // Update links
        const link = this.linkGroup.selectAll('line')
            .data(edges, d => `${d.source}->${d.target}`);
        
        link.exit().remove();
        
        const linkEnter = link.enter().append('line')
            .attr('class', 'link');
        
        const linkAll = linkEnter.merge(link);
        
        // Update nodes
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
            .classed('active', d => d.id === this.activeNode);
        
        // Update labels
        const label = this.labelGroup.selectAll('text')
            .data(nodes, d => d.id);
        
        label.exit().remove();
        
        const labelEnter = label.enter().append('text')
            .attr('class', 'node-label')
            .text(d => d.label);
        
        const labelAll = labelEnter.merge(label);
        
        // Update simulation
        this.simulation.nodes(nodes);
        this.simulation.force('link').links(edges);
        this.simulation.alpha(0.3).restart();
        
        this.simulation.on('tick', () => {
            linkAll
                .attr('x1', d => d.source.x)
                .attr('y1', d => d.source.y)
                .attr('x2', d => d.target.x)
                .attr('y2', d => d.target.y);
            
            nodeAll
                .attr('cx', d => d.x)
                .attr('cy', d => d.y);
            
            labelAll
                .attr('x', d => d.x)
                .attr('y', d => d.y - 15);
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
        d.fx = d.x;
        d.fy = d.y;
    }
    
    dragging(event, d) {
        d.fx = event.x;
        d.fy = event.y;
    }
    
    dragEnd(event, d) {
        if (!event.active) this.simulation.alphaTarget(0);
        d.fx = null;
        d.fy = null;
    }
    
    centerView() {
        const svg = this.svg;
        const width = svg.node().clientWidth;
        const height = svg.node().clientHeight;
        
        svg.transition().duration(750).call(
            d3.zoom().transform,
            d3.zoomIdentity.translate(width / 2, height / 2).scale(1)
        );
    }
    
    updateInstructions() {
        const instructions = d3.select('.instructions');
        if (this.currentMode === 'search') {
            instructions.html('🖱️ <strong>Click</strong> nodes to expand • 🔍 <strong>Search</strong> to add nodes • 📌 <strong>Drag</strong> to move');
        } else {
            instructions.html('🖱️ <strong>Click</strong> to set active node • ➕ <strong>+ Parents/Children</strong> to expand • 📌 <strong>Drag</strong> to move');
        }
    }
}

// Initialize explorer when page loads
document.addEventListener('DOMContentLoaded', () => {
    window.explorer = new SQLiteDependencyExplorer();
});