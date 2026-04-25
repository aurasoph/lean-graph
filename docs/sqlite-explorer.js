// SQLite-based Dependency Explorer
// Uses sql.js to query SQLite databases in the browser

class SQLiteDependencyExplorer {
    constructor() {
        this.currentGraph = 'structures';
        this.currentMode = 'search';
        this.traversalDepth = 1;
        this.expansionDirection = 'all'; // 'all' | 'parents' | 'children'
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
            const query = searchInput.node().value;
            if (query.length < 2) {
                suggestions.style('display', 'none');
                return;
            }
            clearTimeout(this._searchTimer);
            this._searchTimer = setTimeout(() => this.showSuggestions(query), 150);
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

        // Direction toggle
        d3.selectAll('.dir-btn').on('click', (event) => {
            const dir = event.target.dataset.dir;
            this.expansionDirection = dir;
            d3.selectAll('.dir-btn').classed('active', false);
            d3.select(event.target).classed('active', true);
        });
        
        // Click outside to close suggestions
        d3.select('body').on('click', (event) => {
            if (!event.target.closest('.search-section')) {
                suggestions.style('display', 'none');
            }
        });
    }
    
    detectSchema() {
        // unified.db: edges(src, dst, kind) + nodes(name, decl_type, module)
        // standard dbs: nodes(id, label, full_name) + edges(source, target)
        // Distinguish by the 'kind' column on edges, not by table presence.
        const edgeCols = this.queryDB("PRAGMA table_info(edges)").map(r => r.name);
        this.schema = edgeCols.includes('kind') ? 'unified' : 'standard';
    }

    // Schema-aware edge column accessors
    get colSrc() { return this.schema === 'unified' ? 'src' : 'source'; }
    get colDst() { return this.schema === 'unified' ? 'dst' : 'target'; }

    async loadGraph(graphType) {
        this.currentGraph = graphType;
        this.container.select('.loading').style('display', 'flex');

        // Graphs too large to serve online — show message unless running locally
        const LOCAL_ONLY = new Set(['unified', 'type-deps', 'proof-deps']);
        const isLocal = ['localhost', '127.0.0.1', '0.0.0.0'].includes(window.location.hostname);
        if (LOCAL_ONLY.has(graphType) && !isLocal) {
            this.container.select('.loading').html(`
                <div style="text-align:left; max-width:560px; line-height:1.6;">
                    <strong>This graph is too large to serve online.</strong><br><br>
                    Clone the repo and run the local server — the database is included via Git LFS:
                    <pre style="background:#f4f4f4; padding:10px; border-radius:4px; margin-top:8px; font-size:13px; overflow-x:auto;">git lfs install
git clone https://github.com/aurasoph/lean-graph
python3 -m http.server 8000 --directory lean-graph/docs/</pre>
                    See the <a href="https://github.com/aurasoph/lean-graph" target="_blank">README</a> for full setup instructions.
                </div>
            `);
            return;
        }

        try {
            // Load database
            this.container.select('.loading').text(`Loading ${graphType} database...`);
            const dbUrl = `data/${graphType}.db`;
            const dbResponse = await fetch(dbUrl);
            
            if (!dbResponse.ok) {
                throw new Error(`Failed to load ${graphType}.db: ${dbResponse.status}`);
            }
            
            const dbBuffer = await dbResponse.arrayBuffer();
            const dbArray = new Uint8Array(dbBuffer);
            
            this.db = new SQL.Database(dbArray);
            this.detectSchema();

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
        // SQLite LIKE is case-insensitive for ASCII — no LOWER() needed (which breaks index use).
        // For standard schema: search nodes table. For unified: search edge endpoints.
        let prefixMatches, containsMatches;

        if (this.schema === 'standard') {
            prefixMatches = this.queryDB(
                "SELECT id, label, 'prefix' as match_type FROM nodes WHERE id LIKE ? LIMIT 5",
                [`${query}%`]
            );
            containsMatches = this.queryDB(
                "SELECT id, label, 'contains' as match_type FROM nodes WHERE id LIKE ? AND id NOT LIKE ? LIMIT 5",
                [`%${query}%`, `${query}%`]
            );
        } else {
            // unified schema: search nodes table directly
            prefixMatches = this.queryDB(
                "SELECT name as id, name as label, 'prefix' as match_type FROM nodes WHERE name LIKE ? LIMIT 5",
                [`${query}%`]
            );
            containsMatches = this.queryDB(
                "SELECT name as id, name as label, 'contains' as match_type FROM nodes WHERE name LIKE ? AND name NOT LIKE ? LIMIT 5",
                [`%${query}%`, `${query}%`]
            );
        }

        const seen = new Map();
        for (const m of [...prefixMatches, ...containsMatches]) {
            if (!seen.has(m.id)) seen.set(m.id, m);
        }
        const priorityOrder = { 'prefix': 1, 'contains': 2 };
        return Array.from(seen.values())
            .sort((a, b) => (priorityOrder[a.match_type] || 3) - (priorityOrder[b.match_type] || 3))
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
        let matches;
        if (this.schema === 'standard') {
            matches = this.queryDB(
                "SELECT id FROM nodes WHERE id = ? OR id LIKE ? LIMIT 1",
                [query, `%.${query}`]
            );
        } else {
            matches = this.queryDB(
                "SELECT name as id FROM nodes WHERE name = ? OR name LIKE ? LIMIT 1",
                [query, `%.${query}`]
            );
        }
        if (matches.length > 0) {
            this.addNode(matches[0].id);
        } else {
            alert(`Node "${query}" not found`);
        }
    }
    
    addNode(nodeId, expandRelatives = true) {
        if (!this.db) return;
        if (this.schema === 'standard') {
            const nodeExists = this.queryDB("SELECT id FROM nodes WHERE id = ?", [nodeId]);
            if (nodeExists.length === 0) return;
        } else {
            const nodeExists = this.queryDB("SELECT name FROM nodes WHERE name = ?", [nodeId]);
            if (nodeExists.length === 0) return;
        }
        
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
        const src = this.colSrc, dst = this.colDst;
        const dir = this.expansionDirection;
        if (dir !== 'children') {
            const parents = this.queryDB(`SELECT ${src} as src FROM edges WHERE ${dst} = ?`, [nodeId]);
            parents.forEach(edge => {
                this.visibleNodes.add(edge.src);
                this.visibleEdges.add(`${edge.src}->${nodeId}`);
            });
        }
        if (dir !== 'parents') {
            const children = this.queryDB(`SELECT ${dst} as dst FROM edges WHERE ${src} = ?`, [nodeId]);
            children.forEach(edge => {
                this.visibleNodes.add(edge.dst);
                this.visibleEdges.add(`${nodeId}->${edge.dst}`);
            });
        }
    }
    
    setActiveNode(nodeId) {
        this.activeNode = nodeId;
        this.visibleNodes.clear();
        this.visibleEdges.clear();
        this.nodeDistances.clear();
        
        this.visibleNodes.add(nodeId);
        this.nodeDistances.set(nodeId, 0);
        
        // Multi-depth expansion using BFS
        const src = this.colSrc, dst = this.colDst;
        const dir = this.expansionDirection;
        let currentLevelNodes = [nodeId];
        for (let depth = 1; depth <= this.traversalDepth; depth++) {
            let nextLevelNodes = [];
            for (const node of currentLevelNodes) {
                if (dir !== 'children') {
                    const parents = this.queryDB(`SELECT ${src} as src FROM edges WHERE ${dst} = ?`, [node]);
                    parents.forEach(edge => {
                        if (!this.visibleNodes.has(edge.src)) {
                            this.visibleNodes.add(edge.src);
                            this.nodeDistances.set(edge.src, depth);
                            nextLevelNodes.push(edge.src);
                        }
                        this.visibleEdges.add(`${edge.src}->${node}`);
                    });
                }
                if (dir !== 'parents') {
                    const children = this.queryDB(`SELECT ${dst} as dst FROM edges WHERE ${src} = ?`, [node]);
                    children.forEach(edge => {
                        if (!this.visibleNodes.has(edge.dst)) {
                            this.visibleNodes.add(edge.dst);
                            this.nodeDistances.set(edge.dst, depth);
                            nextLevelNodes.push(edge.dst);
                        }
                        this.visibleEdges.add(`${node}->${edge.dst}`);
                    });
                }
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

        let nodes;
        if (this.schema === 'standard') {
            nodes = this.queryDB(
                `SELECT id, label, full_name FROM nodes WHERE id IN (${placeholders})`,
                nodeIds
            );
        } else {
            // unified: query nodes table for metadata; synthesize any not found
            const rows = this.queryDB(
                `SELECT name as id, name as full_name, decl_type, module FROM nodes WHERE name IN (${placeholders})`,
                nodeIds
            );
            const found = new Set(rows.map(r => r.id));
            const missing = nodeIds.filter(id => !found.has(id))
                .map(id => ({ id, full_name: id, decl_type: 'other', module: '' }));
            nodes = [...rows, ...missing];
        }

        // Restore simulation coordinates if they exist
        nodes.forEach(n => {
            const existing = this.simulation?.nodes().find(sn => sn.id === n.id);
            if (existing) { n.x = existing.x; n.y = existing.y; }
        });

        const src = this.colSrc, dst = this.colDst;
        const edges = this.queryDB(
            `SELECT ${src} as source, ${dst} as target FROM edges
             WHERE ${src} IN (${placeholders}) AND ${dst} IN (${placeholders})`,
            [...nodeIds, ...nodeIds]
        );
        
        d3.select('#graph-stats').text(`${nodes.length} nodes, ${edges.length} edges`);
        
        if (!this.simulation) {
            this.simulation = d3.forceSimulation()
                .force('link', d3.forceLink().id(d => d.id).distance(100))
                .force('charge', d3.forceManyBody().strength(-200))
                .force('center', d3.forceCenter(600, 400))
                .force('collision', d3.forceCollide().radius(30))
                .alphaDecay(0.05)
                .velocityDecay(0.5);
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
            .text(d => {
                const name = d.full_name || d.id;
                // For unified nodes use last component only (full names are too long to display)
                return this.schema === 'unified' ? name.split('.').pop() : (d.label || name);
            });

        this.simulation.nodes(nodes);
        this.simulation.force('link').links(edges);

        // Only kick the simulation proportionally to how many nodes are new.
        // If all nodes already had positions, skip the restart entirely.
        const newCount = nodes.filter(n => n.x === undefined).length;
        if (newCount > 0) {
            const alpha = newCount <= 3 ? 0.1 : 0.3;
            this.simulation.alpha(alpha).restart();
        }
        
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
            // Always re-expand with current direction, whether node is new or already visible
            this.visibleNodes.add(d.id);
            this.expandNeighbors(d.id);
            this.render();
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
