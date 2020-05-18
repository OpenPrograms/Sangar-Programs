--[[ This software is licensed under the M.I.T. license.
    Author: David Bergman
    Source: https://code.google.com/p/lualisp/

    This is a Scheme/Lisp interpreter, written in Lua.
    Adjusted for Lua 5.2 and amalgamated for OpenComputers.
    Run it without parameters to get into interpreter mode.
    Alternatively pass it a file name of a lisp script.
]]


local environment = {}

-- Lookup a symbol, going from the most local to the most global scope.
function environment:lookup(symbol)
  for i = self.scopeCount, 1, -1 do
    local tab = self.scopes[i]
    local val = tab[symbol]
    if val then
      return val
    end
  end
  return nil
end

-- Add a new key or change an existing one in the most local scope.
function environment:add(key, value)
  self.scopes[self.scopeCount][key] = value
  return self.scopes[self.scopeCount][key]
end

-- Create a string representation of the environment.
function environment:tostring()
  local str = {}
  table.insert(str, "Environment[scopeCount=" .. self.scopeCount .. "\n")
  for _, scope in ipairs(self.scopes) do
    table.insert(str, "Scope[")
    for k, v in pairs(scope) do
      table.insert(str, tostring(k))
      table.insert(str, "=")
      table.insert(str, tostring(v))
      table.insert(str, " ")
    end
    table.insert(str, "]\n")
  end
  table.insert(str, "]")
  return table.concat(str)
end

function environment:addBindings(formalList, actualList)
  return self:addLocalScope(environment.bind({}, formalList, actualList))
end

function environment.bind(scope, formalList, actualList)
  if formalList.type == "CONS" then
    scope[formalList.car.lexeme] = actualList.car
    return environment.bind(scope, formalList.cdr, actualList.cdr)
  else
    return scope
  end
end

-- Create local scope and return new extended environment.
function environment:addLocalScope(localScope)
  -- Add a new empty local scope.
  local newScopes = {}
  for _, scope in ipairs(self.scopes) do
    table.insert(newScopes, scope)
  end
  table.insert(newScopes, localScope)
  return setmetatable({
    scopeCount = self.scopeCount + 1,
    scopes = newScopes,
    add = environment.add,
    addBindings = environment.addBindins,
    addLocalScope = environment.addLocalScope
  }, environment.mt)
end

environment.mt = {
  __index = environment.lookup,
  __newindex = environment.add,
  __tostring = environment.tostring
}

function environment.new(scope)
  -- The scopes are stored from most global to most local.
  return setmetatable({
    scopeCount = 1,
    scopes = {scope},
    add = environment.add,
    addBindings = environment.addBindings,
    addLocalScope = environment.addLocalScope,
    lookup = environment.lookup
  }, environment.mt)
end

-- Deals with (unevaluated or not) S-expressions, which are simply atoms or CONS cells.
-- The atoms are either:
-- 1. Literals (t or nil)
-- 2. Numericals
-- 3. Operators [',`]
-- 4. Symbols
-- 5. Function references
local Sexpr = {}

Sexpr.constants = {["t"]=true, ["nil"]=true}
Sexpr.mt = {}
function Sexpr.mt.__tostring(expr)
  if expr.type == "CONS" then
    return "(" .. tostring(expr.car) .. " . " .. tostring(expr.cdr) .. ")"
  else
    return "atom[type=" .. expr.type .. ", lex=\"" .. expr.lexeme .. "\"]"
  end
end

-- Atoms

function Sexpr.newBool(cond)
  if cond then
    return Sexpr.newAtom("t")
  else
    return Sexpr.newAtom("nil")
  end
end

function Sexpr.newString(content)
  return setmetatable({type="STR", lexeme=content}, Sexpr.mt)
end

function Sexpr.newOperator(op)
  local type
  if op == "(" then
    type = "LEFTPAREN"
  elseif op == ")" then
    type = "RIGHTPAREN"
  else
    type = "OP"
  end
  return setmetatable({type=type, lexeme=op}, Sexpr.mt)
end

function Sexpr.newAtom(atom)
  -- Make sure to use the string from here on
  atom = tostring(atom)
  local expr
  if Sexpr.constants[atom] then
    expr = {type="LITERAL", lexeme=atom}
  elseif string.find(atom, "^-?%d*.?%d+$") then
    expr = {type="NUM", lexeme=atom}
  else
    expr = {type="SYM", lexeme=atom}
  end
  return setmetatable(expr, Sexpr.mt)
end

-- Create a new function reference, where the special parameter can be nil
-- (for a normal function) or 'lazy' for functions handling their own internal
-- evaluation, or 'macro' for functions mereley replacing their body, for
-- further evaluation.
function Sexpr.newFun(name, fun, special)
  return {type="FUN", lexeme=name, fun=fun, special=special}
end 

function Sexpr.cons(a, b)
  return setmetatable({type="CONS", car=a, cdr=b} , Sexpr.mt)
end

function Sexpr.prettyPrint(sexpr, inList)
  local pretty
  sexpr = sexpr or Sexpr.newAtom("nil")
  if sexpr.type == "CONS" then
    local str = {}
    -- If we are inside a list, we skip the initial '('.
    if inList then
      table.insert(str, " ")
    else
      table.insert(str, "(")
    end
    table.insert(str, Sexpr.prettyPrint(sexpr.car))

    -- Pretty print the CDR part in list mode.
    table.insert(str, Sexpr.prettyPrint(sexpr.cdr, true))

    -- Close with a ')' if we were not in a list mode already.
    if not inList then
      table.insert(str, ")")
    end
    pretty = table.concat(str)
  else
    local str = {}
    if inList and
      (sexpr.type ~= "LITERAL" or sexpr.lexeme ~= "nil") then
      table.insert(str, " . ")
    end
    if sexpr.type == "FUN" then
      if sexpr.special == "macro" then
        table.insert(str, "#macro'")
      else
        table.insert(str, "#'")
      end
    end
    -- We just add the lexeme, unless we are a nil in the end of a list...
    if not inList or sexpr.type ~= "LITERAL" or sexpr.lexeme ~= "nil" then
      if sexpr.type == "STR" then
        table.insert(str, "\"")
      end
      table.insert(str, sexpr.lexeme)
      if sexpr.type == "STR" then
        table.insert(str, "\"")
      end
    end
    pretty = table.concat(str)
  end
  return pretty
end

local parser = {
  operators = {
    ["("] = true, [")"] = true,
    [","] = true, ["'"] = true,
    ["`"] = true, ["."] = true
  }
}

-- Parse the code snippet, yielding a list of (unevaluated) S-expr.
function parser.parseSexpr(expr)
  local tokenList = parser.parseTokens(expr)
  local next = 1
  local sexpr
  local sexprList = {}
  repeat
    next, sexpr = parser.createSexpr(tokenList, next)
    if sexpr then
      table.insert(sexprList, sexpr)
    end
  until not sexpr
  return sexprList
end

function parser.createSexpr(tokens, start)
  -- If the first token is a '(', we should expect a "list".
  local firstToken = tokens[start]
  if not firstToken then
    return start, nil
  end
  if firstToken.type == "LEFTPAREN" then
    return parser.createCons(tokens, start + 1)
  elseif firstToken.type == "OP" then
    local next, cdr = parser.createSexpr(tokens, start + 1)
    return next, Sexpr.cons(firstToken, cdr)
  else
    return start + 1, firstToken
  end
end

function parser.createCons(tokens, start)
  -- If the first token is a '.', we just return the second token, as is,
  -- while skipping a subsequent ')',  else if it is a ')' we return NIL,
  -- else we get the first Sexpr and CONS it with the rest.
  local firstTok = tokens[start]
  if not firstTok then
    error("Token index " .. start .. " is out of range when creating CONS S-Expr", 2)
  end
  if firstTok.type == "OP" and firstTok.lexeme == "." then
    -- We skip the last ')'.
    local next, cdr = parser.createSexpr(tokens, start + 1)      
    if not tokens[next] or tokens[next].type ~= "RIGHTPAREN" then
      error("The CDR part ending with " .. tokens[next - 1].lexeme .. " was not followed by a ')'")
    end
    return next + 1, cdr
  elseif firstTok.type == "RIGHTPAREN" then
    return start + 1, Sexpr.newAtom("nil")
  else
    local next, car = parser.createSexpr(tokens, start)
    local rest, cdr = parser.createCons(tokens, next)
    return rest, Sexpr.cons(car, cdr)
  end
end

-- Parse a sub expression, returning both an expression and
-- the index following this sub expression.
function parser.parseTokens(expr)
  local tokens = {}
  -- We do it character by character, using queues to
  -- handle strings as well as regular lexemes
  local currentToken = {}
  local inString = false
  local isEscaping = false
  for i = 1, string.len(expr) do
    local c = string.sub(expr, i, i)
    -- We have seven (7) main cases:
    if isEscaping then
      -- 1. Escaping this character, whether in a string or not.
      table.insert(currentToken, c)       
      isEscaping = false
    elseif c == "\\" then
      -- 2. An escape character
      isEscaping = true
    elseif c == "\""  then
      -- 3. A quotation mark
      if not inString then
        -- a. starting a new string
        -- If we already had a token, let us finish that up first
        if #currentToken > 0 then
          table.insert(tokens, Sexpr.newAtom(table.concat(currentToken)))
        end
        currentToken = {}
        inString = true
      else
        -- b. ending a string
        table.insert(tokens, Sexpr.newString(table.concat(currentToken)))
        currentToken = {}
        inString = false
      end   
    elseif inString then
      -- 4. inside a string, so just add the character
      table.insert(currentToken, c)
    elseif parser.operators[c] then
      -- 5. special operator (and not inside string)
      -- We add any saved token
      if #currentToken > 0 then
        table.insert(tokens, Sexpr.newAtom(table.concat(currentToken)))
        currentToken = {}
      end
      table.insert(tokens, Sexpr.newOperator(c))
    elseif string.find(c, "%s") then
      -- 6. A blank character, which should add the current token, if any.
      if #currentToken > 0 then
        table.insert(tokens, Sexpr.newAtom(table.concat(currentToken)))
        currentToken = {}
      end
    else
    -- 7. A non-blank character being part of the a symbol
    table.insert(currentToken, c)
    end
  end
  -- Add any trailing token...
  if #currentToken > 0 then
    local atom
    if inString then
      atom = Sexpr.newString(table.concat(currentToken))
    else
      atom = Sexpr.newAtom(table.concat(currentToken))
    end
    table.insert(tokens, atom)
  end
  return tokens
end

local lisp = {}

function lisp.evalExpr(env, expr)
  return lisp.evalSexprList(env, parser.parseSexpr(expr))
end

function lisp.evalQuote(env, sexpr)
  local value
  if not sexpr.type then
    error("Invalid S-expr: ", 2)
  end
  if sexpr.type == "CONS" then
    local car = sexpr.car
    if car.type == "OP" and car.lexeme == "," then
      value = lisp.evalSexpr(env, sexpr.cdr)
    else      
      local evalCar = lisp.evalQuote(env, car)
      local cdr = lisp.evalQuote(env, sexpr.cdr)
      value = Sexpr.cons(evalCar, cdr)
    end
  else
    value = sexpr
  end
  return value
end

function lisp.evalSexprList(env, sexprList, index)
  if not index then
    index = 1
  end
  local count = #sexprList
  if index > count then
    return nil
  else
    local firstValue = lisp.evalSexpr(env, sexprList[index])
    if index == count then
      return firstValue
    else
      return lisp.evalSexprList(env, sexprList, index + 1)
    end
  end
end

function lisp.evalSexpr(env, sexpr)
  local value
  if not sexpr.type then
    error("Invalid S-expr: " .. sexpr, 2)
  end
  if sexpr.type == "CONS" then
    -- 1. Cons cell
    local car = sexpr.car
    if car.type == "OP" and car.lexeme == "'" then
      value = sexpr.cdr
    elseif car.type == "OP" and car.lexeme == "`" then
      value = lisp.evalQuote(env, sexpr.cdr)
    else
      local fun = lisp.evalSexpr(env, car)
      if not fun or fun.type ~= "FUN" then
        error("The S-expr did not evaluate to a function: " .. tostring(car))
      end
      -- The function can be eithe "lazy", in that it deals with
      -- evaluation of its arguments itself, a "macro", which requires
      -- a second evaluation after the macro expansion, or
      -- a regular eager one
      local args
      if fun.special == "lazy" or fun.special == "macro"  then
        args = sexpr.cdr
      else
        args = lisp.evalList(env, sexpr.cdr)
      end
      value = fun.fun(env, args)
    end
  elseif sexpr.type == "SYM" then
    -- a. symbol
    value = env[sexpr.lexeme]
    if not value then
      error("The symbol '" .. sexpr.lexeme .. "' is not defined")
    end
  else
    -- b. constant
    value = sexpr
  end
  return value
end

-- Evaluate each item in a list
function lisp.evalList(env, list)
  if list.type == "CONS" then
    return Sexpr.cons(lisp.evalSexpr(env, list.car),
                      lisp.evalList(env, list.cdr))
  else
    return list
  end
end

-- Apply an environment and get the substituted S-exp
function lisp.applyEnv(env, expr)
  if expr.type == "CONS" then
    return Sexpr.cons(lisp.applyEnv(env, expr.car),
                      lisp.applyEnv(env, expr.cdr))
  elseif expr.type == "SYM" then
    return env[expr.lexeme] or expr
  else
    return expr
  end
end

-- Some primitives

function lisp.prim_car(env, args)
  return args.car.car
end

function lisp.prim_cdr(env, args)
  return args.car.cdr
end

function lisp.prim_cons(env, args)
  return Sexpr.cons(args.car, args.cdr.car)
end

function lisp.prim_plus(env, args, acc)
  if not args or not args.car then
    return Sexpr.newAtom(acc)
  else
    return lisp.prim_plus(env, args.cdr, (acc or 0) + tonumber(lisp.evalSexpr(env, args.car).lexeme))
  end
end

function lisp.prim_mult(env, args, acc)
  if not args or not args.car then
    return Sexpr.newAtom(acc)
  else
    return lisp.prim_mult(env, args.cdr, (acc or 1) * tonumber(lisp.evalSexpr(env, args.car).lexeme))
  end
end

function lisp.prim_lambda(env, args)
  local formalParams = args.car
  local body = args.cdr.car
  return Sexpr.newFun("(lambda " ..
      Sexpr.prettyPrint(formalParams) ..
      " " .. Sexpr.prettyPrint(body) .. ")",
      function(env2, actualParams)
        local localEnv = env:addBindings(formalParams, actualParams)
        return lisp.evalSexpr(localEnv, body)
      end)
end

function lisp.prim_if(env, args)
  local cond = lisp.evalSexpr(env, args.car)
  if cond.type == "LITERAL" and cond.lexeme == "nil" then
    return lisp.evalSexpr(env, args.cdr.cdr.car)
  else
    return lisp.evalSexpr(env, args.cdr.car)
  end
end

function lisp.prim_eq(env, args)
  local arg1 = args.car
  local arg2 = args.cdr.car
  return Sexpr.newBool(arg1.type == arg2.type and arg1.type ~= "CONS" and arg1.lexeme == arg2.lexeme)
end

function lisp.prim_lt(env, args)
  return Sexpr.newBool(tonumber(lisp.evalSexpr(args.car).lexeme) < tonumber(lisp.evalSexpr(args.cdr.car).lexeme))
end

function lisp.prim_consp(env, args)
  return Sexpr.newBool(args.car.type == "CONS")
end

function lisp.prim_neg(env, args)
  if not args or not args.car then
    return Sexpr.newBool(false)
  else
    return Sexpr.cons(Sexpr.newAtom(-tonumber(lisp.evalSexpr(env, args.car).lexeme)), lisp.prim_neg(env, args.cdr))
  end
end

function lisp.prim_setq(env, args)
  local value = lisp.evalSexpr(env, args.cdr.car)
  env[args.car.lexeme] = value
  return value
end

function lisp.prim_eval(env, sexpr)
  local car = sexpr.car
  if car.type == "STR" then
    return lisp.evalExpr(env, car.lexeme)
  else
    return lisp.evalSexpr(env, car)
  end
end

function lisp.prim_load(env, sexpr)
  lisp.runFile(env, sexpr.car.lexeme)
  return Sexpr.newBool(true)
end

function lisp.prim_echo(env, sexpr)
  print(Sexpr.prettyPrint(sexpr.car))
  return Sexpr.newBool(true)
end

function lisp.prim_defmacro(env, sexpr)
  local name = sexpr.car
  local params = sexpr.cdr.car
  local body = sexpr.cdr.cdr.car
  local fun = Sexpr.newFun("(defmacro " .. name.lexeme ..
                           " " .. Sexpr.prettyPrint(params) ..
                           " " .. Sexpr.prettyPrint(body) ..
                           ")", function (env, e)
                             return lisp.evalSexpr(env, lisp.applyEnv(environment.new(environment.bind({}, params, e)), body))
                           end, "macro")
  env[name.lexeme] = fun
  return fun
end

function lisp.getPrimitiveScope()
  return {
    ["car"] = Sexpr.newFun("car", lisp.prim_car),
    ["cdr"] = Sexpr.newFun("cdr", lisp.prim_cdr),
    ["cons"] = Sexpr.newFun("cons", lisp.prim_cons),
    ["lambda"] = Sexpr.newFun("lambda", lisp.prim_lambda, "lazy"),
    ["setq"] = Sexpr.newFun("setq", lisp.prim_setq, "lazy"),
    ["<"] = Sexpr.newFun("<", lisp.prim_lt),
    ["+"] = Sexpr.newFun("+", lisp.prim_plus),
    ["*"] = Sexpr.newFun("*", lisp.prim_mult),
    ["neg"] = Sexpr.newFun("neg", lisp.prim_neg),
    ["eq"] = Sexpr.newFun("eq", lisp.prim_eq),
    ["consp"] = Sexpr.newFun("consp", lisp.prim_consp),
    ["eval"] = Sexpr.newFun("eval", lisp.prim_eval),
    ["load"] = Sexpr.newFun("load", lisp.prim_load),
    ["echo"] = Sexpr.newFun("echo", lisp.prim_echo),
    ["defmacro"] = Sexpr.newFun("defmacro", lisp.prim_defmacro, "lazy"),
    ["if"] = Sexpr.newFun("if", lisp.prim_if, "lazy")
  }
end

function lisp.getGlobalEnv()
  local env = environment.new(lisp.getPrimitiveScope())
  lisp.evalExpr(env, [[
  (defmacro defun (name params body)
    (setq name (lambda params body)))

  (defmacro or (a b)
    (if a a b))

  (defmacro and (a b)
    (if a b nil))

  (defun <= (x y)
    (or (< x y) (eq x y)))

  (defun > (x y)
    (< y x))

  (defun >= (x y)
    (<= y x))

  (defun - (x y)
    (+ (cons x (neg y)))))

  (defun nullp (x)
    (eq x nil))
  ]])
  return env
end

function lisp.runFile(env, filename)
  local f, reason = io.open(filename, "r")
  if not f then
    error(reason)
  end
  local head = f:read("*line")
  if not head then return end
  if head:sub(1, 2) ~= "#!" then
    f:seek("set", 0)
  end
  local code = f:read("*all")
  f:close()
  return lisp.evalExpr(env, code)
end

function lisp.readEval()
  local component = require("component")
  local term = require("term")
  local history = {}
  local env = lisp.getGlobalEnv()
  while term.isAvailable() do
    local foreground = component.gpu.setForeground(0x00FF00)
    term.write("lisp> ")
    component.gpu.setForeground(foreground)
    local code = term.read(history)
    if code == nil then
      return
    end
    while #history > 10 do
      table.remove(history, 1)
    end
    if code then
      local result = table.pack(pcall(lisp.evalExpr, env, code))
      if not result[1] or result.n > 1 then
        for i = 2, result.n do
          if result[i] and type(result[i]) ~= "string" then
            result[i] = Sexpr.prettyPrint(result[i])
          end
        end
        print(table.unpack(result, 2, result.n))
      end
    end
  end
end

local shell = require("shell")
local args = shell.parse(...)

if #args > 0 then
  lisp.runFile(lisp.getGlobalEnv(), shell.resolve(args[1]))
else
  lisp.readEval()
end