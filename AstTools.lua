local lfs = require "lfs"
local cjson = require "cjson"

local function LuaTableDump(pmObj)
    if type(pmObj) == 'table' then
        local dump_str = '{'
        for key, val in pairs(pmObj) do
            if type(key) ~= 'number' then dump_str = dump_str .. key .. '=' end
            dump_str = dump_str .. LuaTableDump(val) .. ','
        end
        dump_str = dump_str .. '}'
        return dump_str
    elseif type(pmObj) == 'string' then
        return '"' .. pmObj .. '"'
    else
        return tostring(pmObj)
    end
end

local function AstDump(pmAstObj)
    local ast_str =
        'astver=' .. tostring(pmAstObj.astver) .. '\n' ..
        'astname="' .. pmAstObj.astname .. '"\n' ..
        'ast=' .. LuaTableDump(pmAstObj.ast)
    return ast_str
end

local function AstLoad(pmAstPath)
    dofile(pmAstPath)
    local ast_table = {
        ["astver"] = astver,
        ["astname"] = astname,
        ["ast"] = ast
    }

    astver          = nil
    astname         = nil
    ast             = nil
    return ast_table
end

local function AstGetBlockWithTextNameList(pmAstObj)
    local block_name_list = {}

    local ast_block_cur_name = "block_00000"
    local ast_block_cur = pmAstObj["ast"][ast_block_cur_name]
    while true do
        if ast_block_cur.text then
            table.insert(block_name_list, ast_block_cur_name)
        elseif ast_block_cur.select then
            table.insert(block_name_list, ast_block_cur_name)
        end
        -- check next block
        ast_block_cur_name = ast_block_cur["linknext"]
        ast_block_cur = pmAstObj["ast"][ast_block_cur_name]
        if ast_block_cur == nil then break end
    end

    return block_name_list
end

local function AstTextExport(pmAstPath, pmLang)
    local function ExportText(pmTextTable)
        local msg_str = ''
        local name_str = ''

        for key, info in pairs(pmTextTable[pmLang][1]) do
            if key == 'name' then -- process name
                if #info == 1 then
                    name_str = info[1]
                elseif #info == 2 then
                    name_str = info[2]
                else
                    assert(false)
                end
            elseif type(info) == 'table' then -- process ctrl
                if info[1] == 'txruby' then
                    if info.text then
                        msg_str = msg_str .. '[txruby=' .. info.text .. ']'
                    else
                        if #info ~= 1 then assert(false) end
                        msg_str = msg_str .. '[@txruby]'
                    end
                elseif info[1] == 'rt2' then
                    if #info ~= 1 then assert(false) end
                    msg_str = msg_str .. '[r]'
                elseif info[1] == 'exfont' then
                    if info.size then
                        msg_str = msg_str .. '[exfont=' .. info.size .. ']'
                    else
                        if #info ~= 1 then assert(false) end
                        msg_str = msg_str .. '[@exfont]'
                    end
                else
                    assert(false)
                end
            elseif type(info) == 'string' then -- process text
                msg_str = msg_str .. info
            else
                assert(false)
            end
        end

        -- insert to table
        local msg_info = {}
        if name_str ~= '' then
            table.insert(msg_info, name_str)
        end
        if msg_str ~= '' then
            table.insert(msg_info, msg_str)
            table.insert(msg_info, msg_str)
        end

        return msg_info
    end

    local function ExportSelect(pmSelectTable)
        local select_info = {}
        for _, select_str in pairs(pmSelectTable[pmLang]) do
            if type(select_str) ~= 'string' then assert(false) end
            table.insert(select_info, select_str)
            table.insert(select_info, select_str)
        end
        return select_info
    end

    pmLang = pmLang or 'ja'

    local texts_list = {}

    local ast_obj = AstLoad(pmAstPath)
    for _, ast_block_name_cur in pairs(AstGetBlockWithTextNameList(ast_obj)) do
        local ast_block_cur = ast_obj["ast"][ast_block_name_cur]
        if ast_block_cur.text then       -- process msg
            table.insert(texts_list, { ["msg"] = ExportText(ast_block_cur.text) })
        elseif ast_block_cur.select then -- process select
            table.insert(texts_list, { ["sel"] = ExportSelect(ast_block_cur.select) })
        end
    end

    return texts_list
end

local function AstTextImprot(pmAstPath, pmJsonPath, pmLang)
    local function ParseTraText(pmTraTextInfo, pmOrgTextTable)
        local function ParseTraStr(pmTraStr, pmTransNameTable)
            local trans_msg_info = { ["name"] = pmTransNameTable }

            local sub_str_beg = 1
            local cur_seq = 1
            while cur_seq < #pmTraStr do
                if pmTraStr:byte(cur_seq) ~= string.byte('[') then
                    cur_seq = cur_seq + 1
                    goto continue
                end

                table.insert(trans_msg_info, pmTraStr:sub(sub_str_beg, cur_seq - 1))

                local token_end_seq = pmTraStr:find(']', cur_seq + 1)
                if token_end_seq == nil then assert(false) end
                local token = pmTraStr:sub(cur_seq, token_end_seq)

                if token == '[r]' then
                    table.insert(trans_msg_info, { "ret2" })
                    cur_seq = token_end_seq + 1;
                elseif token:sub(1, 8) == '[txruby=' then
                    table.insert(trans_msg_info, { "txruby", text = token:sub(9, #token - 1) })
                    local token_pair_end_seq = pmTraStr:find('[@txruby]', token_end_seq + 1)
                    if token_pair_end_seq == nil then assert(false) end
                    table.insert(trans_msg_info, pmTraStr:sub(token_end_seq + 1, token_pair_end_seq - 2))
                    table.insert(trans_msg_info, { "txruby" })
                    cur_seq = token_pair_end_seq + #'[@txruby]' - 1
                elseif token:sub(1, 8) == '[exfont=' then
                    table.insert(trans_msg_info, { "exfont", size = token:sub(9, #token - 1) })
                    local token_pair_end_seq = pmTraStr:find('[@exfont]', token_end_seq + 1)
                    if token_pair_end_seq == nil then assert(false) end
                    table.insert(trans_msg_info, pmTraStr:sub(token_end_seq + 1, token_pair_end_seq - 2))
                    table.insert(trans_msg_info, { "exfont" })
                    cur_seq = token_pair_end_seq + #"[@exfont]" - 1
                else
                    assert(false)
                end

                sub_str_beg = cur_seq

                ::continue::
            end

            if sub_str_beg ~= cur_seq then assert(false) end
            return trans_msg_info
        end

        local function ParseTraChar(pmOrgNameTable, pmTraNameStr)
            if pmOrgNameTable then
                local name_info = {}
                if #pmOrgNameTable == 1 then
                    table.insert(name_info, pmTraNameStr)
                elseif #pmOrgNameTable == 2 then
                    table.insert(name_info, pmOrgNameTable[1])
                    table.insert(name_info, pmTraNameStr)
                end
                return name_info
            else
                return nil
            end
        end

        return { ParseTraStr(pmTraTextInfo[#pmTraTextInfo], ParseTraChar(pmOrgTextTable["name"], pmTraTextInfo[1])) }
    end

    local function ParseTraSelect(pmTraSelect, pmOrgSelectLen)
        local select_info = {}
        for index = 1, #pmTraSelect, 2 do
            table.insert(select_info, pmTraSelect[index])
        end
        if #select_info ~= pmOrgSelectLen then assert(false) end
        return select_info
    end

    local function InfoJsonLoad(pmPath, pmAstTextBlockCnt)
        local ifs = assert(io.open(pmPath, "r"))
        local info_obj = cjson.decode(ifs:read("a"))
        ifs:close()
        if #info_obj ~= pmAstTextBlockCnt then assert(false) end
        return info_obj
    end

    pmLang = pmLang or 'ja'

    local ast_obj = AstLoad(pmAstPath)
    local block_name_list = AstGetBlockWithTextNameList(ast_obj)
    local info_obj = InfoJsonLoad(pmJsonPath, #block_name_list)
    for index = 1, #block_name_list do
        local ast_cur = ast_obj["ast"][block_name_list[index]]
        local info_cur = info_obj[index];

        if ast_cur["text"] then -- process test
            if info_cur["msg"] == nil then assert(false) end
            ast_cur["text"][pmLang] = ParseTraText(info_cur["msg"], ast_cur["text"][pmLang][1])
        elseif ast_cur["select"] then -- process select
            if info_cur["sel"] == nil then assert(false) end
            ast_cur["select"][pmLang] = ParseTraSelect(info_cur["sel"], #ast_cur["select"][pmLang])
        end
    end

    return ast_obj
end


local function AstBatchTextExport(pmAstFolder, pmSaveFolder, pmLang)
    lfs.mkdir(pmSaveFolder)

    for ast_filename in lfs.dir(pmAstFolder) do
        if ast_filename == '.' then goto continue end
        if ast_filename == '..' then goto continue end

        print('process: ' .. ast_filename)
        local export_text_table = AstTextExport(pmAstFolder .. ast_filename, pmLang)
        local export_text_json_str = cjson.encode(export_text_table)
        local export_text_json_path = pmSaveFolder .. ast_filename .. '.json'
        local ofs = assert(io.open(export_text_json_path, "w"))
        ofs:write(export_text_json_str)
        ofs:close()
        ::continue::
    end
end

local function AstBatchTextImport(pmAstFolder, pmJsonFolder, pmSaveFolder)
    lfs.mkdir(pmSaveFolder)

    for ast_filename in lfs.dir(pmAstFolder) do
        if ast_filename == '.' then goto continue end
        if ast_filename == '..' then goto continue end

        print('process: ' .. ast_filename)
        local ast_data = AstDump(AstTextImprot(pmAstFolder .. ast_filename, pmJsonFolder .. ast_filename .. '.json'))
        local ast_save_path = pmSaveFolder .. ast_filename
        local ofs = assert(io.open(ast_save_path, "w"))
        ofs:write(ast_data)
        ofs:close()
        ::continue::
    end
end

local function AstBatchCompress(pmAstFolder, pmSaveFolder)
    lfs.mkdir(pmSaveFolder)

    for ast_filename in lfs.dir(pmAstFolder) do
        if ast_filename == '.' then goto continue end
        if ast_filename == '..' then goto continue end

        print('process: ' .. ast_filename)

        local ast_obj = AstLoad(pmAstFolder .. ast_filename)
        local ast_str = AstDump(ast_obj)
        local ast_save_path = pmSaveFolder .. ast_filename
        local ofs = assert(io.open(ast_save_path, "w"))
        ofs:write(ast_str)
        ofs:close()

        ::continue::
    end
end


return {
    Dump = AstDump,
    BatchCompress = AstBatchCompress,
    BatchTextExport = AstBatchTextExport,
    BatchTextImport = AstBatchTextImport,
    TextExport = AstTextExport,
    TextImport = AstTextImprot,
    Load = AstLoad,
}
