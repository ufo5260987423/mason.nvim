local path = require "nvim-lsp-installer.path"
local process = require "nvim-lsp-installer.process"
local installers = require "nvim-lsp-installer.installers"
local shell = require "nvim-lsp-installer.installers.shell"

local M = {}

function M.download_file(url, out_file)
    return installers.when {
        unix = function(server, callback, context)
            process.spawn("wget", {
                args = { "-nv", "-O", out_file, url },
                cwd = server.root_dir,
                stdio_sink = context.stdio_sink,
            }, callback)
        end,
        win = shell.powershell(("iwr -Uri %q -OutFile %q"):format(url, out_file)),
    }
end

function M.unzip(file, dest)
    return installers.when {
        unix = function(server, callback, context)
            process.spawn("unzip", {
                args = { "-d", dest, file },
                cwd = server.root_dir,
                stdio_sink = context.stdio_sink,
            }, callback)
        end,
        win = shell.powershell(("Expand-Archive -Path %q -DestinationPath %q"):format(file, dest)),
    }
end

function M.unzip_remote(url, dest)
    return installers.pipe {
        M.download_file(url, "archive.zip"),
        M.unzip("archive.zip", dest or "."),
        installers.always_succeed(M.delete_file "archive.zip"),
    }
end

function M.untar(file)
    return installers.pipe {
        function(server, callback, context)
            process.spawn("tar", {
                args = { "-xvf", file },
                cwd = server.root_dir,
                stdio_sink = context.stdio_sink,
            }, callback)
        end,
        installers.always_succeed(M.delete_file(file)),
    }
end

function M.untargz_remote(url)
    return installers.pipe {
        M.download_file(url, "archive.tar.gz"),
        M.gunzip "archive.tar.gz",
        M.untar "archive.tar",
        installers.always_succeed(M.delete_file "archive.tar"),
    }
end

function M.gunzip(file)
    return function(server, callback, context)
        process.spawn("gzip", {
            args = { "-d", file },
            cwd = server.root_dir,
            stdio_sink = context.stdio_sink,
        }, callback)
    end
end

function M.gunzip_remote(url, out_file)
    local archive = ("%s.gz"):format(out_file or "archive")
    return installers.pipe {
        M.download_file(url, archive),
        M.gunzip(archive),
        installers.always_succeed(M.delete_file(archive)),
    }
end

function M.delete_file(file)
    return installers.when {
        unix = function(server, callback, context)
            process.spawn("rm", {
                args = { "-f", file },
                cwd = server.root_dir,
                stdio_sink = context.stdio_sink,
            }, callback)
        end,
        win = shell.powershell(("rm %q"):format(file)),
    }
end

function M.git_clone(repo_url)
    return function(server, callback, context)
        process.spawn("git", {
            args = { "clone", "--depth", "1", repo_url, "." },
            cwd = server.root_dir,
            stdio_sink = context.stdio_sink,
        }, callback)
    end
end

function M.gradlew(opts)
    return function(server, callback, context)
        process.spawn(path.concat { server.root_dir, "gradlew" }, {
            args = opts.args,
            cwd = server.root_dir,
            stdio_sink = context.stdio_sink,
        }, callback)
    end
end

function M.ensure_executables(executables)
    return vim.schedule_wrap(function(_, callback, context)
        for i = 1, #executables do
            local executable = executables[i]
            if vim.fn.executable(executable) ~= 1 then
                context.stdio_sink.stderr(("Missing required %q executable."):format(executable))
                callback(false)
                return
            end
        end
        callback(true)
    end)
end

function M.chmod(flags, files)
    return installers.on {
        unix = function(server, callback, context)
            process.spawn("chmod", {
                args = vim.list_extend({ flags }, files),
                cwd = server.root_dir,
                stdio_sink = context.stdio_sink,
            }, callback)
        end,
    }
end

return M
