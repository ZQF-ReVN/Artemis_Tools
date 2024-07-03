local AstTools = require "AstTools"

-- AstTools.BatchCompress('script/', 'compressed/')

-- AstTools.BatchTextImport('script/','json_cn/','import/')

-- AstTools.BatchTextExport('script/', 'json/')

-- test

local ast_data = AstTools.Dump(AstTools.TextImport("script/1.ast","json_cn/1.ast.json"))
local ast_save_path = "1.ast"
local ofs = assert(io.open(ast_save_path, "w"))
ofs:write(ast_data)
ofs:close()