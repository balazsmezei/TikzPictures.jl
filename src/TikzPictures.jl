module TikzPictures

export TikzPicture, PDF, TEX, TIKZ, SVG, save, tikzDeleteIntermediate, tikzCommand, TikzDocument, push!
import Base: push!
import LaTeXStrings: LaTeXString, @L_str, @L_mstr
export LaTeXString, @L_str, @L_mstr

_tikzDeleteIntermediate = true
_tikzCommand = "lualatex"
_tikzUsePDF2SVG = true


# standalone workaround:
# see http://tex.stackexchange.com/questions/315025/lualatex-texlive-2016-standalone-undefined-control-sequence
_standaloneWorkaround = false

function standaloneWorkaround()
    global _standaloneWorkaround
    _standaloneWorkaround
end

function standaloneWorkaround(value::Bool)
    global _standaloneWorkaround
    _standaloneWorkaround = value
    nothing
end

function tikzDeleteIntermediate(value::Bool)
    global _tikzDeleteIntermediate
    _tikzDeleteIntermediate = value
    nothing
end

function tikzDeleteIntermediate()
    global _tikzDeleteIntermediate
    _tikzDeleteIntermediate
end

function tikzCommand(value::AbstractString)
    global _tikzCommand
    _tikzCommand = value
    nothing
end

function tikzCommand()
    global _tikzCommand
    _tikzCommand
end

function tikzUsePDF2SVG(value::Bool)
    global _tikzUsePDF2SVG
    _tikzUsePDF2SVG = value
    nothing
end

function tikzUsePDF2SVG()
    global _tikzUsePDF2SVG
    _tikzUsePDF2SVG
end

mutable struct TikzPicture
    data::AbstractString
    options::AbstractString
    preamble::AbstractString
    enableWrite18::Bool
    TikzPicture(data::AbstractString; options="", preamble="", enableWrite18=true) = new(data, options, preamble, enableWrite18)
end

mutable struct TikzDocument
    pictures::Vector{TikzPicture}
    captions::Vector{AbstractString}
end

TikzDocument() = TikzDocument(TikzPicture[], String[])

function push!(td::TikzDocument, tp::TikzPicture; caption="")
    push!(td.pictures, tp)
    push!(td.captions, caption)
end

function removeExtension(filename::AbstractString, extension::AbstractString)
    if endswith(filename, extension) || endswith(filename, uppercase(extension))
        return filename[1:(end - length(extension))]
    else
        return filename
    end
end

abstract type SaveType end

mutable struct PDF <: SaveType
    filename::AbstractString
    PDF(filename::AbstractString) = new(removeExtension(filename, ".pdf"))
end

mutable struct TEX <: SaveType
    filename::AbstractString
    include_preamble::Bool
    TEX(filename::AbstractString; include_preamble::Bool=true) = new(removeExtension(filename, ".tex"), include_preamble)
end

mutable struct TIKZ <: SaveType
    filename::AbstractString
    include_preamble::Bool
    TIKZ(filename::AbstractString) = new(removeExtension(filename, ".tikz"), false)
end

mutable struct SVG <: SaveType
    filename::AbstractString
    SVG(filename::AbstractString) = new(removeExtension(filename, ".svg"))
end

extension(f::SaveType) = lowercase(split("$(typeof(f))",".")[end])

showable(::MIME"image/svg+xml", tp::TikzPicture) = true

function save(f::Union{TEX,TIKZ}, tp::TikzPicture)
    filename = f.filename
    ext = extension(f)
    open("$(filename).$(ext)", "w") do io
        if f.include_preamble
            standaloneWorkaround() && println(io, "\\RequirePackage{luatex85}")
            println(io, "\\documentclass[tikz]{standalone}")
            println(io, tp.preamble)
            println(io, "\\begin{document}")
        end
        println(io, "\\begin{tikzpicture}[", tp.options, "]")
        println(io, tp.data)
        println(io, "\\end{tikzpicture}")
        f.include_preamble && println(io, "\\end{document}")
    end
end

function save(f::TEX, td::TikzDocument)
    if isempty(td.pictures)
        error("TikzDocument does not contain pictures")
    end
    filename = f.filename
    open("$(filename).tex", "w") do io
        if f.include_preamble
            println(io, "\\documentclass{article}")
            println(io, "\\usepackage{caption}")
            println(io, "\\usepackage{tikz}")
            println(io, td.pictures[1].preamble)
            println(io, "\\begin{document}")
        end
        println(io, "\\centering")
        @assert length(td.pictures) == length(td.captions)
        for (tp, caption) in zip(td.pictures, td.captions)
            println(io, "\\centering")
            println(io, "\\begin{tikzpicture}[", tp.options, "]")
            println(io, tp.data)
            println(io, "\\end{tikzpicture}")
            println(io, "\\captionof{figure}{", caption, "}")
            println(io, "\\vspace{5ex}")
            println(io)
        end
        f.include_preamble && println(io, "\\end{document}")
    end
end

function latexerrormsg(s)
    beginError = false
    for l in split(s, '\n')
        if beginError
            if !isempty(l) && l[1] == '?'
                return
            else
                println(l)
            end
        else
            if !isempty(l) && l[1] == '!'
                println(l)
                beginError = true
            end
        end
    end
end

function save(f::PDF, tp::TikzPicture)
    basefilename = basename(f.filename)
    dest = abspath(f.filename * ".pdf")

    cd_temp() do
        temp_filename = basefilename

        # Save the TEX file in tmp dir
        save(TEX(temp_filename * ".tex"), tp)

        # From the .tex file, generate a pdf within the tmp folder
        latexCommand = ``
        if tp.enableWrite18
            latexCommand = `$(tikzCommand()) --enable-write18 $(temp_filename*".tex")`
        else
            latexCommand = `$(tikzCommand()) $(temp_filename*".tex")`
        end

        latexSuccess = success(latexCommand)

        tex_log = ""
        try
            tex_log = read(temp_filename * ".log", String)
        catch
            tex_log = read("texput.log", String)
        end

        if occursin("LaTeX Warning: Label(s)", tex_log)
            latexSuccess = success(latexCommand)
        end

        # Move PDF out of tmpdir regardless
        # Give warning if PDF file already exists
        if latexSuccess
            _mv("$(temp_filename).pdf", dest)
        end

        if !latexSuccess
            # Remove failed attempt.
            if !standaloneWorkaround() && occursin("\\sa@placebox ->\\newpage \\global \\pdfpagewidth", tex_log)
                @info "Enabling standalone workaround."
                standaloneWorkaround(true)
                save(f, tp)
                return
            end
            latexerrormsg(tex_log)
            error("LaTeX error")
        end
    end
end

function save(f::PDF, td::TikzDocument)
    basefilename = basename(f.filename)
    dest = abspath(f.filename * ".pdf")

    cd_temp() do
        temp_filename = basefilename

        try
            save(TEX(temp_filename * ".tex"), td)
            if td.pictures[1].enableWrite18
                success(`$(tikzCommand()) --enable-write18 $(temp_filename)`)
            else
                success(`$(tikzCommand()) $(temp_filename)`)
            end

            # Move PDF out of tmpdir regardless
            _mv("$(temp_filename).pdf", dest)
        catch
            @warn "Error saving as PDF."
            rethrow()
        end
    end
end


function save(f::SVG, tp::TikzPicture)
    basefilename = basename(f.filename)
    dest = abspath(f.filename * ".svg")

    cd_temp() do
        temp_filename = basefilename

        # Save the TEX file in tmp dir
        save(TEX(temp_filename * ".tex"), tp)

        if tikzUsePDF2SVG()
            # Convert to PDF and then to SVG
            latexCommand = ``
            if tp.enableWrite18
                latexCommand = `$(tikzCommand()) --enable-write18 $(temp_filename*".tex")`
            else
                latexCommand = `$(tikzCommand()) $(temp_filename*".tex")`
            end

            latexSuccess = success(latexCommand)

            tex_log = read(temp_filename * ".log", String)

            if occursin("LaTeX Warning: Label(s)", tex_log)
                success(latexCommand)
            end

            if !latexSuccess
            # Remove failed attempt.
                if !standaloneWorkaround() && occursin("\\sa@placebox ->\\newpage \\global \\pdfpagewidth", tex_log)
                    @info "Enabling standalone workaround."
                    standaloneWorkaround(true)
                    save(f, tp)
                    return
                end
                latexerrormsg(tex_log)
                error("LaTeX error")
            end

            # Convert PDF file in tmpdir to SVG file in tmpdir
            success(`pdf2svg $(temp_filename).pdf $(temp_filename).svg`) || error("pdf2svg failure")

        else
            luaSucc = false
            if tp.enableWrite18
                luaSucc = success(`$(tikzCommand()) --enable-write18 --output-format=dvi $(temp_filename*".tex")`)
            else
                luaSucc = success(`$(tikzCommand()) --output-format=dvi $(temp_filename*".tex")`)
            end
            dviSuccess = success(`dvisvgm --no-fonts $(temp_filename*".dvi")`)

            # Commands fail silently so check if SVG exists and throw error with warning if not
            if !luaSucc || !dviSuccess
                error("Direct output to SVG failed! Please consider using PDF2SVG")
            end
        end

        _mv("$(temp_filename).svg", dest)
    end
end

# this is needed to work with multiple images in ijulia (kind of a hack)
global _tikzid = round(UInt64, time() * 1e6)


function Base.show(f::IO, ::MIME"image/svg+xml", tp::TikzPicture)
    global _tikzid
    filename = tempname()
    try
        save(SVG(filename), tp)
        s = read("$filename.svg", String)
        s = replace(s, "glyph" => "glyph-$(_tikzid)-")
        s = replace(s, "\"clip" => "\"clip-$(_tikzid)-")
        s = replace(s, "#clip" => "#clip-$(_tikzid)-")
        s = replace(s, "\"image" => "\"image-$(_tikzid)-")
        s = replace(s, "#image" => "#image-$(_tikzid)-")
        s = replace(s, "linearGradient id=\"linear" => "linearGradient id=\"linear-$(_tikzid)-")
        s = replace(s, "#linear" => "#linear-$(_tikzid)-")
        s = replace(s, "image id=\"" => "image style=\"image-rendering: pixelated;\" id=\"")
        _tikzid += 1
        println(f, s)
    finally
        if tikzDeleteIntermediate()
            rm("$filename.svg")
        end
    end
end

function cd_temp(fn::Function, parent=tempdir())
    tmpdir = mktempdir(parent)
    try
        cd(fn, tmpdir)
    finally
        if (tikzDeleteIntermediate())
            try
                rm(tmpdir, recursive=true)
            catch ex
                @error "TikzPictures: Your intermediate files are not being deleted. ($(tmpdir))" _group=:file exception=(ex, catch_backtrace())
            end
        end
    end
end

function _mv(source, dest; warn=true)
    if(warn && isfile(dest))
        @warn "File $(dest) already exists, overwriting!"
    end
    mv(source, dest, force=true)
end

end # module
