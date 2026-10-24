using System;
using System.Security;
using Microsoft.AspNetCore.Mvc;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Services;
using GSSystemAnalyzer.Interfaces;

namespace GSSystemAnalyzer.Controllers;

[ApiController]
[Route("api/[controller]")]
public class StartupController : ControllerBase
{
    private readonly IStartupManager _startupManager;

    public StartupController(IStartupManager startupManager)
    {
        _startupManager = startupManager;
    }

    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var entries = await _startupManager.GetStartupEntriesAsync();
        return Ok(entries);
    }

    [HttpPost("{id}/enable")]
    public async Task<IActionResult> EnableStartup([FromRoute] string id, [FromQuery] string? scope = null)
    {
        try
        {
            await _startupManager.ToggleStartupEntryAsync(id, enable: true, scope: scope);
            return Ok(new { message = $"Successfully enabled startup entry: {id}" });
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException || ex is SecurityException)
        {
            return StatusCode(403, new { error = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new {error = "An unexpected error occurred while enabling the application.", details = ex.Message });
        }
    }

    [HttpPost("{id}/disable")]
    public async Task<IActionResult> DisableStartup([FromRoute] string id, [FromQuery] string? scope = null)
    {
        try
        {
            await _startupManager.ToggleStartupEntryAsync(id, enable: false, scope: scope);
            return Ok(new { message = $"Successfully disabled startup entry: {id}" });
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException || ex is SecurityException)
        {
            return StatusCode(403, new { error = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { error = "An unexpected error occurred while disabling the application.", details = ex.Message });
        }
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> DeleteStartup([FromRoute] string id)
    {
        try
        {
            await _startupManager.DeleteStartupEntryAsync(id);
            return Ok(new { message = $"Successfully deleted startup entry: {id}" });
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException || ex is SecurityException)
        {
            return StatusCode(403, new { error = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new {error = "An unexpected error occurred while deleting the application.", details = ex.Message });
        }
    }
}